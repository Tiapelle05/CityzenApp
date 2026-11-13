-- Pulizia concordata: tabelle mai lette/scritte da nessun endpoint, e i 4
-- device placeholder del vecchio schema a 4 nodi separati (superato da
-- mini_node, un solo ESP32 per zona con tutti i sensori combinati).

DROP TABLE IF EXISTS notify;
DROP TABLE IF EXISTS device_health;
DROP TABLE IF EXISTS event_environment;

DELETE FROM device WHERE mac_address IN (
    'mini:01:amb:01:01:01',
    'mini:02:var:02:02:02',
    'mini:03:bin:03:03:03',
    'mini:04:dsp:04:04:04'
);
