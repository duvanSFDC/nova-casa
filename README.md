# Nova Casa · Sprint 2: señales IoT en Salesforce

Las señales de los edificios llegan desde el simulador, entran como Platform Event y quedan registradas en Salesforce. Este repo cubre **US-201: recibir señales de los edificios** y **US-202: procesar la colección sin perder las válidas**.

## Cómo fluye una señal

1. `TelemetryIngestionService` pide un lote al simulador (`GET /telemetry`) con el cursor guardado en `Ingestion_State__c`.
2. Cada item se convierte en un `Telemetry_Signal__e` y se publica. Por cada evento se crea un `Signal_Log__c` en estado **Published**, junto con su `EventUuid`.
3. El trigger `TelemetrySignalTrigger` recibe el lote y el suscriptor lo procesa en una sola transacción:
   - **Apex A (`TelemetrySignalValidator`)** revisa que cada señal traiga lo que exige su tipo de mensaje. No consulta nada. Una señal incompleta o con un `messageType` desconocido se aparta con su motivo y no llega a Apex B.
   - **Apex B (`TelemetrySignalProcessor`)** reconoce el edificio y el equipo por su código con una sola consulta a `Location` y otra a `Asset`, y revisa que la medición sea compatible con el tipo de equipo (según `Measurement_Threshold__mdt`). El costo es el mismo para 1 o 200 señales: 3 consultas y 1 escritura, sin SOQL ni DML por señal.
4. Cada log pasa a **Processed** con su hora, su `ReplayId` y el resultado del negocio: `Result__c` (Accepted/Rejected), `Reason__c` (por qué se rechazó), el detalle legible en `Error__c`, si conviene reintentar (`Retry_Safe__c`) y el enlace al equipo y al edificio que se reconocieron. Una señal inválida no frena a las demás: todo el lote se guarda con un `upsert` parcial.

Así "publicada" y "procesada" son dos estados del mismo registro (`Status__c`), distintos del resultado del negocio (`Result__c`). Si el bus rechaza la publicación, el log queda en **Publish_Failed** con el error.

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
- `classes/TelemetrySignalValidator` (Apex A), `TelemetrySignalProcessor` (Apex B), `MeasurementCatalog` (lee los umbrales de la CMDT sin gastar consultas) y `TelemetrySignalOutcome` (el resultado de cada señal).
- `objects/Measurement_Threshold__mdt` y sus registros en `customMetadata/`: qué unidad acepta cada tipo de equipo y medición. Se editan sin redesplegar (BR-204).
- `platformEventSubscriberConfigs/TelemetrySignalTriggerConfig`: hace que el suscriptor reciba hasta 200 eventos por invocación.
- `permissionsets/Nova_Integration`: acceso a los objetos y las clases de la ingesta. `permissionsets/Nova_Admin`: acceso de solo lectura a la traza para Camila.

## Antes de empezar

1. La org debe tener la **External Credential** y la **Named Credential** `Nova_Simulator`, con el token en el principal `Nova_Team`, y el permission set **Nova Simulator Access** asignado. El token se configura solo en la org y nunca se sube a este repo.
2. Hay que tener el Salesforce CLI (`sf`) autenticado contra la org. Aquí el alias es `novacasa`.

## Recorrido reproducible

```bash
# 1. Desplegar y correr las pruebas
sf project deploy start --source-dir force-app --target-org novacasa \
  --test-level RunSpecifiedTests \
  --tests TelemetryIngestionServiceTest --tests TelemetryIngestionCursorTest \
  --tests TelemetrySignalValidatorTest --tests TelemetrySignalProcessingTest \
  --tests OperatorStatusServiceTest

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

## Evidencia US-202 (30 de septiembre de 2026)

Con los códigos del simulador cargados en los edificios y equipos, una corrida real trajo **200 señales en un lote** y las 200 quedaron en Processed. El reparto por resultado:

| Resultado | Motivo | Cantidad |
| --- | --- | --- |
| Accepted | — | 195 |
| Rejected | INCOMPLETE (`measurement.value` nulo) | 2 |
| Rejected | UNKNOWN_ASSET (`AST-UNKNOWN-0001`) | 1 |
| Rejected | INCOMPATIBLE_UNIT (energía en `WATT`) | 2 |

Las 195 aceptadas quedaron enlazadas a su equipo, repartidas entre los 9 equipos de Nova Alameda y Nova Caribe (entre 13 y 27 señales por equipo). Las inválidas no frenaron a las válidas y cada una explica su rechazo, por ejemplo *"Llegó en WATT y ENERGY_CONSUMPTION se mide en KWH_PER_15_MIN."*. El conteo se hace sobre todos los logs, no sobre una sola invocación del suscriptor, así que sigue siendo válido aunque la plataforma parta el lote en varias entregas.

La prueba automática `TelemetrySignalProcessingTest` cubre lo mismo de forma determinista: un lote mixto, un lote de 200 con conteos exactos (120/40/20/20) y una prueba que comprueba que 1 y 200 señales cuestan igual (3 consultas, 1 escritura).

## Decisiones

- **Validar y resolver en la misma transacción, con guardado parcial.** El suscriptor corre Apex A y Apex B sobre todo el lote y guarda con `Database.upsert(logs, false, ...)`. Así una señal inválida no tumba a las válidas (BR-202). No se relanza el lote con `RetryableException`, porque un error de datos fallaría igual en cada reintento y el trigger terminaría suspendido.
- **Riesgo aceptado: un fallo de guardado solo queda en el debug.** Si el `upsert` de un log falla, el error se registra con `System.debug` (que como *Automated Process* casi no se captura) y ese log se queda en Published. Es poco probable (el objeto es sencillo y la integración tiene FLS), y resolverlo bien pide un objeto o evento de errores aparte; queda para una historia futura.
- **Las comparaciones no distinguen mayúsculas ni espacios.** Los códigos de edificio, equipo, tipo de mensaje, medición y unidad se normalizan antes de comparar, para que un `bar` o un `BAR ` del origen no provoquen un rechazo falso.
- **La compatibilidad sale de la CMDT, no del código.** La unidad válida de cada medición vive en `Measurement_Threshold__mdt` y se lee con `getAll()` (sin SOQL). Cambiar un umbral no exige redesplegar (BR-204). Además, la medición se compara contra el tipo de equipo guardado en Salesforce, no contra el que trae el mensaje.
- **La ingesta corre en modo sistema.** Desde la API 67, Apex consulta en modo usuario por defecto. El suscriptor corre como *Automated Process*, así que el estado y los logs se leen y escriben con `SYSTEM_MODE` explícito. La seguridad por usuario (BR-208) se aplica en lo que consultan Laura, Javier y Camila.
- **Una sola sesión del simulador.** Cada `POST /session` es un escenario nuevo, así que solo se abre cuando no hay cursor o cuando la sesión vence (dura 30 días).
- **Ritmo de consulta.** El simulador sugiere esperar 10 segundos entre lotes, pero un Queueable no puede esperar menos de 1 minuto. Por eso el job se vuelve a encolar cada minuto.

## Lo que mostró el simulador

- **Hay duplicados.** `msg_000014` llegó dos veces, con `deliveryId` distintos (`dlv_000014` y `dlv_000018`) y el mismo `occurredAt`. Hoy se registran las dos entregas. La clave para detectar el duplicado es `messageId`, no `deliveryId`.
- **El reloj es simulado.** `occurredAt` puede quedar adelante de la hora real de Salesforce. Para saber si una señal llegó atrasada, hay que comparar `occurredAt` entre señales del mismo activo, no contra la hora de Salesforce.
