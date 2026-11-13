-- Reset completo dei device: verranno riregistrati uno per uno con MAC
-- reale e zona (A/B) definitiva. Il CASCADE elimina anche eventi, allarmi,
-- log video e chiavi API collegati a quei device. Le pratiche (tabella
-- practice) NON vengono toccate: restano come storico.
DELETE FROM device;
