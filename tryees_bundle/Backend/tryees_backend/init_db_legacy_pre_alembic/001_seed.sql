INSERT INTO app_user (username, password, type) VALUES
  ('admin',       '$2b$12$GPVAdkxvUqiWHbouW7pHrObyrzRdruVnrH7Qp264Ohtt1cJ4NGtgG', 'admin'),
  ('polizia',     '$2b$12$GPVAdkxvUqiWHbouW7pHrObyrzRdruVnrH7Qp264Ohtt1cJ4NGtgG', 'ente'),
  ('eco',         '$2b$12$GPVAdkxvUqiWHbouW7pHrObyrzRdruVnrH7Qp264Ohtt1cJ4NGtgG', 'op_eco'),
  ('manutenzione','$2b$12$GPVAdkxvUqiWHbouW7pHrObyrzRdruVnrH7Qp264Ohtt1cJ4NGtgG', 'op_eco'),
  ('modellino',   '$2b$12$GPVAdkxvUqiWHbouW7pHrObyrzRdruVnrH7Qp264Ohtt1cJ4NGtgG', 'admin')
ON CONFLICT (username) DO UPDATE SET password=EXCLUDED.password;

-- Elimina device fuori parco o con coordinate sbagliate
DELETE FROM device WHERE mac_address NOT IN ('c0:74:2b:fb:00:3f');

-- Tutti i device DENTRO il Parco Robinson, Legnano
-- Centro parco ≈ 45.6035, 8.9384
-- Telecamera reale: c0:74:2b:fb:00:3f @ 45.603215, 8.938087 (punto rosso foto)
-- Punto verde foto ≈ 45.603580, 8.938260 (circa 40m nord della cam)

INSERT INTO device (mac_address, zone, type, lat, lon) VALUES
  -- Telecamere (4) - angoli del parco + ingresso
  ('c0:74:2b:fb:00:3f', 'Ingresso Sud',          'camera',      45.603215, 8.938087),
  ('a4:cf:12:7e:01:b2', 'Viale Centrale Nord',   'camera',      45.603920, 8.938150),
  ('b8:27:eb:44:02:c1', 'Area Giochi',           'camera',      45.603750, 8.938580),
  ('dc:a6:32:88:03:d4', 'Zona Panchine Ovest',   'camera',      45.603480, 8.937820),
  -- Microfoni (3)
  ('e4:5f:01:cc:04:a7', 'Ingresso Sud',          'microphone',  45.603260, 8.938120),
  ('f0:9f:c2:11:05:b3', 'Viale Centrale Centro', 'microphone',  45.603600, 8.938200),
  ('00:1b:44:99:06:e8', 'Area Giochi',           'microphone',  45.603780, 8.938540),
  -- Cestini smart (5) - lungo i viali e area giochi
  ('14:91:82:3f:07:c5', 'Ingresso Sud',          'basket',      45.603310, 8.938050),
  ('28:cd:c1:77:08:f2', 'Viale Centrale Centro', 'basket',      45.603590, 8.938310),
  ('3c:71:bf:55:09:a1', 'Area Giochi',           'basket',      45.603820, 8.938490),
  ('50:3e:aa:12:10:d6', 'Zona Panchine Ovest',   'basket',      45.603450, 8.937900),
  ('64:b5:c6:88:11:e3', 'Fontana Centrale',      'basket',      45.603640, 8.938080),
  -- Luci (4) - lungo il viale principale
  ('78:8a:20:34:12:b0', 'Ingresso Sud',          'light',       45.603280, 8.938000),
  ('8c:f3:19:67:13:9d', 'Viale Centrale Sud',    'light',       45.603480, 8.938140),
  ('a0:e4:53:ab:14:8a', 'Viale Centrale Nord',   'light',       45.603720, 8.938220),
  ('b4:e6:2d:ff:15:77', 'Area Giochi',           'light',       45.603850, 8.938420),
  -- Sensore suolo (1) - prato centrale
  ('c8:d7:19:44:16:64', 'Prato Centrale',        'soil_sensor', 45.603560, 8.938350)
ON CONFLICT (mac_address) DO UPDATE SET
  zone=EXCLUDED.zone, type=EXCLUDED.type,
  lat=EXCLUDED.lat, lon=EXCLUDED.lon;
