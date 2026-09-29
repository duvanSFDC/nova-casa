# Nova Casa · Sprint 2: señales IoT en Salesforce

Las señales de los edificios llegan desde el simulador, entran como Platform Event y quedan registradas en Salesforce. Este repo cubre **US-201: recibir señales de los edificios**.

## Cómo fluye una señal

1. `TelemetryIngestionService` pide un lote al simulador (`GET /telemetry`) con el cursor guardado en `Ingestion_State__c`.
2. Cada item se convierte en un `Telemetry_Signal__e` y se publica. Por cada evento se crea un `Signal_Log__c` en estado **Published**, junto con su `EventUuid`.
3. El trigger `TelemetrySignalTrigger` recibe el evento y pasa el mismo log a **Processed**, con la hora de procesamiento y el `ReplayId`.

Así "publicada" y "procesada" son dos estados distintos del mismo registro. Si el bus rechaza la publicación, el log queda en **Publish_Failed** con el error.

Cada log guarda cuatro horas por separado:

| Campo | Qué es |
| --- | --- |
| `Occurred_At__c` | Cuándo midió el sensor (`occurredAt`) |
| `Source_Published_At__c` | Cuándo lo publicó el simulador (`publishedAt`) |
| `Published_At__c` | Cuándo Salesforce lo publicó en el bus |
| `Processed_At__c` | Cuándo el suscriptor lo procesó |

## Qué hay en el repo

- `objects/Telemetry_Signal__e`: el contrato. Tiene edificio, activo, medición, valor, unidad, fecha de origen, `messageId` y `deliveryId`, y guarda el payload crudo.
- `objects/Signal_Log__c`: la traza de cada señal.
- `objects/Ingestion_State__c`: el cursor del simulador y cuándo vence la sesión. Es un objeto y no un Custom Setting, porque el cursor pasa de 255 caracteres.
- `classes/NovaSimulatorClient`: las llamadas HTTP, usando la Named Credential `Nova_Simulator`.
- `classes/TelemetrySignalMapper`, `TelemetryPublisher`, `TelemetrySignalSubscriber`, `TelemetryIngestionService` y `TelemetryIngestionJob` (el Queueable).
- `permissionsets/Nova_Integration`: acceso a los objetos y las clases de la ingesta.

## Antes de empezar

1. La org debe tener la **External Credential** y la **Named Credential** `Nova_Simulator`, con el token en el principal `Nova_Team`, y el permission set **Nova Simulator Access** asignado. El token se configura solo en la org y nunca se sube a este repo.
2. Hay que tener el Salesforce CLI (`sf`) autenticado contra la org. Aquí el alias es `novacasa`.

## Recorrido reproducible

```bash
# 1. Desplegar y correr las pruebas
sf project deploy start --source-dir force-app --target-org novacasa \
  --test-level RunSpecifiedTests \
  --tests TelemetryIngestionServiceTest --tests TelemetryIngestionCursorTest

# 2. Dar acceso a quien ejecuta (tu usuario y el de integración)
sf org assign permset --name Nova_Integration --target-org novacasa

# 3. Traer un lote real del simulador
sf apex run --file scripts/apex/ingest-once.apex --target-org novacasa

# 4. Ver la traza (esperar unos segundos a que procese el suscriptor)
sf data query --file scripts/soql/signal-trace.soql --target-org novacasa
```

Para seguir leyendo lotes en segundo plano está `scripts/apex/ingest-async.apex`. Para empezar un escenario nuevo del simulador, `scripts/apex/reset-session.apex`, que borra el cursor guardado.

## Evidencia (28 de septiembre de 2026)

Con una corrida real se recibieron 20 señales, se publicaron 20 y las 20 terminaron en Processed. Por ejemplo, este es el recorrido de una clave:

| | |
| --- | --- |
| `messageId` / `deliveryId` | `msg_000015` / `dlv_000015` (CONNECTIVITY) |
| Log | `LOG-000037` · EventUuid `5ff90c39-0368-4e3a-94c5-299bd8c5294d` |
| Estado | Published → Processed |
| Horas | publicada en Salesforce 04:14:55 · procesada 04:14:57 (UTC) |

## Decisiones

- **La ingesta corre en modo sistema.** Desde la API 67, Apex consulta en modo usuario por defecto. El suscriptor corre como *Automated Process*, así que el estado y los logs se leen y escriben con `SYSTEM_MODE` explícito. La seguridad por usuario (BR-208) se aplica en lo que consultan Laura, Javier y Camila.
- **Una sola sesión del simulador.** Cada `POST /session` es un escenario nuevo, así que solo se abre cuando no hay cursor o cuando la sesión vence (dura 30 días).
- **Ritmo de consulta.** El simulador sugiere esperar 10 segundos entre lotes, pero un Queueable no puede esperar menos de 1 minuto. Por eso el job se vuelve a encolar cada minuto.

## Lo que mostró el simulador

- **Hay duplicados.** `msg_000014` llegó dos veces, con `deliveryId` distintos (`dlv_000014` y `dlv_000018`) y el mismo `occurredAt`. Hoy se registran las dos entregas. La clave para detectar el duplicado es `messageId`, no `deliveryId`.
- **El reloj es simulado.** `occurredAt` puede quedar adelante de la hora real de Salesforce. Para saber si una señal llegó atrasada, hay que comparar `occurredAt` entre señales del mismo activo, no contra la hora de Salesforce.
