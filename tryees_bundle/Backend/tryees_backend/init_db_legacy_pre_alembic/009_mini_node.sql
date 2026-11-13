-- Un ESP32 fisico manda TUTTI i suoi sensori (ambiente + varchi + bin) in un
-- unico payload MQTT: 'mini_node' rappresenta questo caso, invece di dover
-- registrare 3 device separati per lo stesso identico modulo fisico.
-- Le zone si distinguono per Device.zone (es. "Modellino Zona A"/"Zona B"),
-- non per il tipo device.
ALTER TYPE type_device ADD VALUE IF NOT EXISTS 'mini_node';
