/*
 * TreeEyes — Nodo Cestino (Smart Bin) con vero DEEP SLEEP
 * LED: CATODO COMUNE (HIGH accende, LOW spegne).
 *
 * Contratto con il backend (app/core/mqtt.py):
 *   parco/<id>/heartbeat          -> aggiorna solo last_seen (device "online")
 *   parco/<id>/events             -> "full" crea l'evento cestino; "tilt_angle"
 *                                    oltre la soglia vandal_tilt_deg apre la
 *                                    pratica "vandalismo_cestino"
 *   parco/<id>/cmd                <- {"led":"red"} quando il cestino è pieno
 *   smartcity/actuators/alarm     <- {"device_id":..., "sirena":true|false}
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <I2Cdev.h>
#include <MPU6050.h>
#include <Adafruit_VL53L0X.h>
#include <esp_sleep.h>

// ── CONFIGURAZIONE ──────────────────────────────────────────────
const char* WIFI_SSID     = "Parco-IoT";
const char* WIFI_PASSWORD = "1234567890";
const char* MQTT_BROKER   = "192.168.88.10";
const int   MQTT_PORT     = 1883;
const char* MQTT_USER     = "";   // vuoti = broker anonimo (mosquitto.conf attuale)
const char* MQTT_PASS     = "";
const String DEVICE_ID    = "mini:node:cestino";  // deve coincidere con il mac_address registrato sul server

// Il server considera offline un device che tace da 30 minuti
// (DEVICE_OFFLINE_THRESHOLD_MIN): l'heartbeat deve restare ben sotto.
const uint64_t HEARTBEAT_INTERVAL_US   = 10ULL * 60 * 1000000ULL;  // 10 minuti
const uint32_t FILL_EVERY_N_HEARTBEATS = 72;                       // 72 x 10 min = lettura forzata ogni 12 ore
const float    FILL_REPORT_DELTA_PCT   = 5.0;   // sotto questa variazione si manda solo l'heartbeat

const float BIN_DEPTH_MM = 300.0;
const unsigned long ALARM_DURATION_MS = 10000;  // la sirena suona 10 secondi, poi si spegne sempre
const unsigned long LED_SHOW_MS       = 4000;   // LED di riempimento acceso dopo PIR / riavvio
const unsigned long LISTEN_MS         = 1000;   // ascolto comandi sui risvegli da timer
const float TILT_BASE_DEG   = 90.0;             // inclinazione letta a riposo (MPU montato in verticale): diventa 0
const float VANDAL_TILT_DEG = 45.0;             // scostamento dalla base che fa scattare l'allarme (= vandal_tilt_deg sul server)

// ── PIN ──
#define PIN_PIR       27
#define PIN_MPU_INT   26
#define PIN_SPEAKER   25
#define PIN_RGB_R     16
#define PIN_RGB_G     17
#define PIN_RGB_B     18  // <-- VERIFICA QUESTO CAVETTO SUL LED FISICO PER IL BLU

const char* TOPIC_ALARM = "smartcity/actuators/alarm";
const int ALARM_FREQ_LOW  = 700;
const int ALARM_FREQ_HIGH = 1200;

MPU6050 mpu;
Adafruit_VL53L0X tof;
WiFiClient   wifiClient;
PubSubClient mqtt(wifiClient);

// Sopravvivono al deep sleep (memoria RTC)
RTC_DATA_ATTR float    lastFillPct         = 0.0;   // ultima misura valida
RTC_DATA_ATTR float    lastSentFillPct     = -1.0;  // ultima misura arrivata al server (-1 = mai)
RTC_DATA_ATTR uint32_t heartbeatsSinceFill = 0;

bool remoteAlarmRequested = false;
bool alarmStopRequested   = false;
bool vandalismoReported   = false;
float alarmTiltDeg        = 0.0;   // inclinazione (già corretta) che ha fatto scattare l'allarme

String topicEvents()    { return String("parco/") + DEVICE_ID + "/events"; }
String topicHeartbeat() { return String("parco/") + DEVICE_ID + "/heartbeat"; }
String topicCmd()       { return String("parco/") + DEVICE_ID + "/cmd"; }

// Catodo Comune pulito: HIGH accende
void setRGBColor(bool r, bool g, bool b) {
  digitalWrite(PIN_RGB_R, r ? HIGH : LOW);
  digitalWrite(PIN_RGB_G, g ? HIGH : LOW);
  digitalWrite(PIN_RGB_B, b ? HIGH : LOW);
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, payload, length) != DeserializationError::Ok) return;

  // Comando diretto al cestino: il server non mette device_id nel payload,
  // il destinatario è nel topic.
  if (String(topic) == topicCmd()) {
    const char* led = doc["led"];
    if (led != nullptr && String(led) == "red") setRGBColor(true, false, false);
    return;
  }

  if (String(topic) == TOPIC_ALARM) {
    const char* targetId = doc["device_id"];
    if (targetId == nullptr || String(targetId) != DEVICE_ID) return;
    if (doc["sirena"] | false) remoteAlarmRequested = true;
    else                       alarmStopRequested = true;   // riarmo dal pannello
  }
}

void startWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

bool connectMqtt() {
  if (mqtt.connected()) return true;
  if (WiFi.status() != WL_CONNECTED) return false;

  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  mqtt.setBufferSize(512);
  mqtt.setSocketTimeout(2);
  String clientId = "esp32-" + DEVICE_ID;
  unsigned long mstart = millis();
  while (!mqtt.connected() && millis() - mstart < 2000) {
    if (strlen(MQTT_USER) > 0) mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS);
    else                       mqtt.connect(clientId.c_str());
    if (!mqtt.connected()) delay(100);
  }
  if (!mqtt.connected()) return false;

  mqtt.subscribe(TOPIC_ALARM);
  mqtt.subscribe(topicCmd().c_str());
  return true;
}

bool connectWiFiAndMqtt() {
  if (WiFi.status() != WL_CONNECTED) {
    startWiFi();
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 4000) delay(100);
  }
  return connectMqtt();
}

bool publishJson(const String& topic, JsonDocument& doc) {
  if (!mqtt.connected()) return false;
  char buf[256];
  size_t n = serializeJson(doc, buf);
  return mqtt.publish(topic.c_str(), (const uint8_t*)buf, n);
}

bool sendHeartbeat() {
  if (!connectWiFiAndMqtt()) return false;
  StaticJsonDocument<256> doc;
  doc["device_id"] = DEVICE_ID;
  doc["type"]      = "heartbeat";
  doc["status"]    = "online";
  bool ok = publishJson(topicHeartbeat(), doc);
  Serial.println(ok ? "[MQTT] Heartbeat inviato" : "[MQTT] Heartbeat NON inviato");
  return ok;
}

// Inclinazione rispetto alla posizione di riposo: l'MPU legge TILT_BASE_DEG
// (90°) a cestino dritto, quindi si sottrae la base -> 0° a riposo.
// Media su ~200 ms per non farsi ingannare dai picchi di un urto.
float readTiltDeg() {
  long sx = 0, sy = 0, sz = 0;
  for (int i = 0; i < 20; i++) {
    int16_t ax, ay, az;
    mpu.getAcceleration(&ax, &ay, &az);
    sx += ax; sy += ay; sz += az;
    delay(10);
  }
  float x = sx / 20.0f, y = sy / 20.0f, z = sz / 20.0f;
  float magnitude = sqrt(x*x + y*y + z*z);
  if (magnitude < 1.0f) return 0.0;   // lettura non valida
  float rawDeg = acos(z / magnitude) * 180.0f / PI;   // angolo fra asse Z e gravità
  float tiltDeg = fabs(rawDeg - TILT_BASE_DEG);
  Serial.print("[MPU] Inclinazione letta: "); Serial.print(rawDeg);
  Serial.print("  -> corretta: "); Serial.println(tiltDeg);
  return tiltDeg;
}

bool sendFillEvent(float fillPct, float tiltDeg) {
  if (!connectWiFiAndMqtt()) return false;
  StaticJsonDocument<256> doc;
  doc["device_id"]      = DEVICE_ID;
  doc["full"]           = fillPct;
  doc["fill_level_pct"] = fillPct;
  doc["tilt_angle"]     = tiltDeg;
  return publishJson(topicEvents(), doc);
}

void soundAlarm(bool reportVandalismo);

// Resta in ascolto dei comandi del server; una richiesta di sirena fa partire
// l'allarme locale (sempre limitato a ALARM_DURATION_MS).
void listenForCommands(unsigned long ms) {
  unsigned long start = millis();
  while (millis() - start < ms) {
    if (mqtt.connected()) mqtt.loop();
    if (remoteAlarmRequested) {
      remoteAlarmRequested = false;
      soundAlarm(false);
      return;
    }
    delay(10);
  }
}

void handleFillReading(bool forceReport) {
  bool measured = tof.begin();
  float fillPct = lastFillPct;

  if (measured) {
    VL53L0X_RangingMeasurementData_t m;
    tof.rangingTest(&m, false);

    float distMm = (m.RangeStatus != 4 && m.RangeMilliMeter < 500) ? m.RangeMilliMeter : BIN_DEPTH_MM;
    fillPct = (1.0f - (distMm / BIN_DEPTH_MM)) * 100.0f;
    if (fillPct < 0) fillPct = 0;
    if (fillPct > 100) fillPct = 100;
    lastFillPct = fillPct;

    Serial.print("[VL53L0X] Percentuale calcolata: "); Serial.println(fillPct);

    // --- LOGICA SOGLIE AGGIORNATA (>85% ROSSO) ---
    if (fillPct < 60.0) {
      setRGBColor(false, true, false);  // VERDE
    } else if (fillPct >= 60.0 && fillPct < 85.0) {
      setRGBColor(true, true, false);   // GIALLO
    } else {
      setRGBColor(true, false, false);  // ROSSO
    }
  } else {
    setRGBColor(false, true, false); // Fail-safe Verde
  }

  // Ogni evento "full" apre o aggiorna una pratica "Cestino pieno" sul server:
  // si manda solo se il livello è cambiato davvero (o sulla lettura forzata),
  // altrimenti basta l'heartbeat per restare online.
  bool changed = lastSentFillPct < 0 || fabs(fillPct - lastSentFillPct) >= FILL_REPORT_DELTA_PCT;
  if (measured && (forceReport || changed)) {
    if (sendFillEvent(fillPct, readTiltDeg())) {
      lastSentFillPct = fillPct;
      heartbeatsSinceFill = 0;
    }
  } else {
    sendHeartbeat();
  }
}

void soundAlarm(bool reportVandalismo) {
  Serial.println("!!! ALLARME SIRENA AVVIATO !!!");
  unsigned long lastToggle = 0;
  bool toggleState = false;
  bool tried = false;
  alarmStopRequested = false;
  vandalismoReported = false;

  unsigned long alarmStart = millis();
  while (millis() - alarmStart < ALARM_DURATION_MS && !alarmStopRequested) {
    // Lampeggio Sirena Polizia (Rosso / Blu alternati ogni 200ms)
    if (millis() - lastToggle >= 200) {
      lastToggle = millis();
      toggleState = !toggleState;

      if (toggleState) {
        tone(PIN_SPEAKER, ALARM_FREQ_HIGH);
        setRGBColor(true, false, false); // ROSSO
      } else {
        tone(PIN_SPEAKER, ALARM_FREQ_LOW);
        setRGBColor(false, false, true); // BLU
      }
    }

    // Segnala il vandalismo appena il WiFi è su, senza aspettare la fine
    // della sirena (un solo tentativo, non negli ultimi secondi per non
    // sforare la durata se il broker non risponde).
    if (reportVandalismo && !tried && WiFi.status() == WL_CONNECTED && millis() - alarmStart < ALARM_DURATION_MS - 4000) {
      tried = true;
      vandalismoReported = sendFillEvent(lastFillPct, alarmTiltDeg);
    }

    if (mqtt.connected()) mqtt.loop();
    delay(10);
  }
  noTone(PIN_SPEAKER);
  digitalWrite(PIN_SPEAKER, LOW);
  setRGBColor(false, false, false); // Spegne tutto
  alarmStopRequested = false;
  remoteAlarmRequested = false;     // una richiesta arrivata durante la sirena non la fa ripartire
}

void handleVandalismo() {
  // L'allarme scatta sull'inclinazione già corretta (lettura - 90°)
  alarmTiltDeg = readTiltDeg();
  if (alarmTiltDeg < VANDAL_TILT_DEG) {
    Serial.println("[MPU] Movimento senza inclinazione oltre soglia: nessun allarme");
    return;
  }

  startWiFi();        // si connette in background mentre la sirena suona
  soundAlarm(true);

  // Se durante la sirena non è partito, riprova a sirena spenta
  if (!vandalismoReported) vandalismoReported = sendFillEvent(lastFillPct, alarmTiltDeg);
  Serial.println(vandalismoReported ? "[MQTT] Vandalismo segnalato al server"
                                    : "[MQTT] Vandalismo NON segnalato (server irraggiungibile)");
}

void configureMpuMotionInterrupt() {
  mpu.initialize();
  mpu.setSleepEnabled(false);
  mpu.setDLPFMode(MPU6050_DLPF_BW_256);
  mpu.setMotionDetectionThreshold(1); // Iper-sensibile per il banco prova
  mpu.setMotionDetectionDuration(1);
  mpu.setIntMotionEnabled(true);
  mpu.setIntZeroMotionEnabled(false);
  mpu.setIntFIFOBufferOverflowEnabled(false);
}

void goToSleep() {
  Serial.println("Spegnimento LED e ingresso in Deep Sleep...");
  setRGBColor(false, false, false);

  // Chiusura pulita: garantisce che l'ultimo publish parta prima dello sleep
  if (mqtt.connected()) { mqtt.loop(); delay(100); mqtt.disconnect(); }
  WiFi.disconnect(true);

  mpu.getIntStatus();  // azzera un eventuale interrupt di movimento ancora pendente
  esp_sleep_enable_ext1_wakeup((1ULL << PIN_PIR) | (1ULL << PIN_MPU_INT), ESP_EXT1_WAKEUP_ANY_HIGH);
  esp_sleep_enable_timer_wakeup(HEARTBEAT_INTERVAL_US);
  Serial.flush();
  esp_deep_sleep_start();
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(PIN_PIR, INPUT);
  pinMode(PIN_SPEAKER, OUTPUT);
  pinMode(PIN_RGB_R, OUTPUT);
  pinMode(PIN_RGB_G, OUTPUT);
  pinMode(PIN_RGB_B, OUTPUT);

  digitalWrite(PIN_SPEAKER, LOW);
  setRGBColor(false, false, false);

  Wire.begin();
  configureMpuMotionInterrupt();

  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  Serial.print("[SVEGLIA] Causa risveglio: "); Serial.println(cause);

  if (cause == ESP_SLEEP_WAKEUP_EXT1) {
    uint64_t wakePins = esp_sleep_get_ext1_wakeup_status();
    if (wakePins & (1ULL << PIN_MPU_INT)) {
      Serial.println(">>> SVEGLIATO DA: MPU6050 (URTO) <<<");
      handleVandalismo();
    } else {
      Serial.println(">>> SVEGLIATO DA: PIR (PRESENZA) <<<");
      handleFillReading(false);
      listenForCommands(LED_SHOW_MS);
    }
  } else if (cause == ESP_SLEEP_WAKEUP_TIMER) {
    heartbeatsSinceFill++;
    if (heartbeatsSinceFill >= FILL_EVERY_N_HEARTBEATS) {
      Serial.println(">>> SVEGLIATO DA: TIMER (LETTURA PERIODICA) <<<");
      handleFillReading(true);
    } else {
      Serial.println(">>> SVEGLIATO DA: TIMER (HEARTBEAT) <<<");
      sendHeartbeat();
    }
    listenForCommands(LISTEN_MS);
  } else {
    Serial.println(">>> RIAVVIO <<<");
    handleFillReading(true);
    listenForCommands(LED_SHOW_MS);
  }

  goToSleep();
}

void loop() {
  // Tutto eseguito in setup()
}
