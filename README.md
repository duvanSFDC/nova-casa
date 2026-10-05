# Nova Casa · Sprint 2: señales IoT en Salesforce

Las señales de los edificios llegan desde el simulador, entran como Platform Event y quedan registradas en Salesforce. Este repo cubre **US-201: recibir señales de los edificios**, **US-202: procesar la colección sin perder las válidas**, **US-203: mantener el estado actual por activo y medición**, **US-204/US-206: límites y severidad** y **US-205: una sola intervención por mensaje crítico**.

## Cómo fluye una señal

1. `TelemetryIngestionService` pide un lote al simulador (`GET /telemetry`) con el cursor guardado en `Ingestion_State__c`.
2. Cada item se convierte en un `Telemetry_Signal__e` y se publica. Por cada evento se crea un `Signal_Log__c` en estado **Published**, junto con su `EventUuid`.
3. El trigger `TelemetrySignalTrigger` recibe el lote y el suscriptor lo procesa en una sola transacción:
   - **Apex A (`TelemetrySignalValidator`)** revisa que cada señal traiga lo que exige su tipo de mensaje. No consulta nada. Una señal incompleta o con un `messageType` desconocido se aparta con su motivo y no llega a Apex B.
   - **Apex B parte 1 (`TelemetrySignalProcessor`)** reconoce el edificio y el equipo por su código con una sola consulta a `Location` y otra a `Asset`, revisa que la medición sea compatible con el tipo de equipo y clasifica la severidad (`MeasurementSeverityClassifier`, según `Measurement_Threshold__mdt`).
   - **Identidad (`SignalIdentityService`, BR-205)** aparta los reenvíos (quedan **Duplicate** y reutilizan el resultado existente) y los conflictos (misma identidad con contenido distinto → **IDENTITY_CONFLICT**) por `messageId`, antes de tocar el estado o crear intervenciones.
   - **Apex B parte 2 (`AssetConditionService`)** mantiene la lectura más reciente por activo y tipo de medición en `Asset_Condition__c`: agrupa las aceptadas por su llave (`AssetId:tipo`), conserva la de mayor `occurredAt` y hace un solo `upsert` por la llave única. Una señal que no es más nueva que la lectura actual no reemplaza el estado: queda **Atrasada** (Late).
   - **Intervención (`InterventionService`, BR-205)** abre una sola intervención (`WorkOrder`) por cada crítica vigente, con `Message_Key__c = messageId` como llave única; los reenvíos reutilizan la existente.
   - El costo es por lote, no por señal: hasta 6 consultas y 3 escrituras aunque lleguen 200 señales.
4. Cada log pasa a **Processed** con su hora, su `ReplayId` y el resultado del negocio: `Result__c` (Accepted/Rejected/Late), `Reason__c` (por qué se rechazó), el detalle legible en `Error__c`, si conviene reintentar (`Retry_Safe__c`) y el enlace al equipo y al edificio que se reconocieron. Una señal inválida no frena a las demás: todo el lote se guarda con un `upsert` parcial.

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
- `classes/TelemetrySignalValidator` (Apex A), `TelemetrySignalProcessor` (Apex B parte 1), `AssetConditionService` (Apex B parte 2: estado actual), `SignalIdentityService` (reenvíos y conflictos por identidad), `InterventionService` (abre la intervención por mensaje crítico), `MeasurementSeverityClassifier` (clasifica Normal/Warning/Critical con los umbrales), `MeasurementCatalog` (lee la unidad de la CMDT sin gastar consultas) y `TelemetrySignalOutcome` (el resultado de cada señal).
- `objects/Asset_Condition__c`: el estado actual, una fila por activo y tipo de medición (`Asset_Measurement_Key__c = AssetId:tipo`). Es lo que lee la pantalla de Laura.
- `objects/Measurement_Threshold__mdt` y sus registros en `customMetadata/`: qué unidad acepta cada tipo de equipo y medición. Se editan sin redesplegar (BR-204).
- `platformEventSubscriberConfigs/TelemetrySignalTriggerConfig`: hace que el suscriptor reciba hasta 200 eventos por invocación.
- `classes/OperatorStatusService` y `lwc/operatorStatus`: la pantalla *Estado operativo* de Laura (lecturas vigentes, estado del activo e intervención abierta). `permissionsets/Nova_Operator`: el acceso de Laura a esa pantalla.
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
  --tests TelemetryStateProcessingTest --tests MeasurementSeverityClassifierTest \
  --tests TelemetrySignalSeverityTest --tests InterventionProcessingTest \
  --tests OperatorStatusServiceTest

# 1b. Pruebas de la pantalla (Jest)
npm install && npm run test:unit

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

La prueba automática `TelemetrySignalProcessingTest` cubre lo mismo de forma determinista: un lote mixto, un lote de 200 y una prueba que comprueba que 1 y 200 señales cuestan igual.

## Evidencia US-203 (1 de octubre de 2026)

Una corrida real de **200 señales** quedó así: **17 Accepted, 177 Late y 6 Rejected** (1 `INCOMPLETE`, 4 `UNKNOWN_ASSET`, 1 `INCOMPATIBLE_UNIT`). El estado actual quedó en **9 filas de `Asset_Condition__c`**, una por activo y tipo de medición (presión, temperatura, consumo de agua y de energía de cada edificio, más la conectividad de la cámara), cada una con su lectura más reciente.

Que haya **17 aceptadas pero solo 9 filas de estado** es justo lo que pide la historia: el bus entregó las 200 en varias invocaciones del suscriptor y, en cada una, solo la lectura más reciente de cada activo avanzó el estado; las demás quedaron Late. Una señal con `occurredAt` igual o más viejo nunca pisa la lectura actual, sin importar su severidad.

La prueba automática `TelemetryStateProcessingTest` cubre esto de forma determinista: llegada en orden y fuera de orden entre publicaciones y dentro de una misma colección, el empate exacto de `occurredAt`, la conectividad (se queda el último estado, sin valor ni unidad) y que 200 señales mantienen el costo acotado por lote.

## Evidencia US-205 (2 de octubre de 2026)

El camino crítico → intervención se prueba de forma determinista con `InterventionProcessingTest` (8 casos): una crítica crea **una** intervención con activo, edificio, causa, severidad (`Priority = Critical`) y seguimiento (`Status = New`); un reenvío entre entregas no crea una segunda y reutiliza la existente; un duplicado dentro de la colección deja una sola; una misma identidad con contenido distinto es conflicto; una crítica atrasada no abre intervención; una falla de creación deja la señal como `Rejected`/`INTERVENTION_FAILED` reintentable (nunca procesada sin su resultado); y 200 críticas mantienen el costo en 6 consultas y 3 escrituras por lote.

En una corrida real de **200 señales** el flujo integrado quedó así: **15 Accepted, 8 Duplicate, 175 Late y 2 Rejected**. Los 8 duplicados muestran la deduplicación por identidad funcionando en vivo (el simulador reenvía mensajes). En ese lote no llegó ninguna crítica (las presiones reales estuvieron sobre el umbral), así que no se abrieron intervenciones; la clasificación crítica depende de los umbrales reales que entregará Emiliano.

## Evidencia US-206 (5 de octubre de 2026)

Se publicaron al bus 11 señales de prueba (`Source = us-206-evidence`, `Delivery_Id` `dlv_us206_*`) contra los límites de ejemplo de la CMDT. Las 11 quedaron **Processed / Accepted** con esta severidad:

| Señal | Activo | Valor | Límites (dirección) | Severidad | Work Order |
| --- | --- | --- | --- | --- | --- |
| Representativa | Bomba principal de agua | 3.2 bar | 1.5 / 1.0 (Below) | Normal | — |
| Representativa | Ventilación | 32 °C | 30 / 35 (Above) | Warning | — |
| Representativa | Medidor de energía Bogotá | 65 kWh/15 min | 40 / 60 (Above) | Critical | 00000144 |
| Límite | Medidor de agua Bogotá | 599.9 · 600 · 999.9 · 1000 L/15 min | 600 / 1000 (Above) | Normal · Warning · Warning · Critical | solo 1000 → 00000145 |
| Límite | Bomba de agua Caribe | 1.6 · 1.5 · 1.1 · 1.0 bar | 1.5 / 1.0 (Below) | Normal · Warning · Warning · Critical | solo 1.0 → 00000146 |

Solo las críticas abrieron intervención (por el camino de US-205); normal y advertencia solo actualizaron la lectura. En la pantalla *Estado operativo* los tres activos críticos quedaron arriba con *Crítico* en rojo y su Work Order, luego las advertencias y al final los normales y el activo sin lectura. Las pruebas `OperatorStatusServiceTest` (estado del activo, filtro y conectividad) y las de Jest de `operatorStatus` cubren lo mismo de forma determinista; los límites exactos ya los cubre `MeasurementSeverityClassifierTest`.

## Decisiones

- **Validar y resolver en la misma transacción, con guardado parcial.** El suscriptor corre Apex A y Apex B sobre todo el lote y guarda con `Database.upsert(logs, false, ...)`. Así una señal inválida no tumba a las válidas (BR-202). No se relanza el lote con `RetryableException`, porque un error de datos fallaría igual en cada reintento y el trigger terminaría suspendido.
- **Riesgo aceptado: un fallo de guardado solo queda en el debug.** Si el `upsert` de un log falla, el error se registra con `System.debug` (que como *Automated Process* casi no se captura) y ese log se queda en Published. Es poco probable (el objeto es sencillo y la integración tiene FLS), y resolverlo bien pide un objeto o evento de errores aparte; queda para una historia futura.
- **Las comparaciones no distinguen mayúsculas ni espacios.** Los códigos de edificio, equipo, tipo de mensaje, medición y unidad se normalizan antes de comparar, para que un `bar` o un `BAR ` del origen no provoquen un rechazo falso.
- **La compatibilidad sale de la CMDT, no del código.** La unidad válida de cada medición vive en `Measurement_Threshold__mdt` y se lee con `getAll()` (sin SOQL). Cambiar un umbral no exige redesplegar (BR-204). Además, la medición se compara contra el tipo de equipo guardado en Salesforce, no contra el que trae el mensaje.
- **Solo una lectura estrictamente más nueva reemplaza el estado (BR-203).** Se compara por `occurredAt`, nunca contra `Datetime.now()`. En empate exacto de `occurredAt` se conserva la lectura actual y la que llega queda Atrasada (Late); así se cumple el KPI de "0 sobrescrituras". La regla vale igual dentro de una colección y entre publicaciones, aunque el bus parta el lote en varias invocaciones del suscriptor.
- **Una señal atrasada no dispara acción.** Una lectura más vieja (o empatada) queda Late y no actualiza `Asset_Condition__c` ni abre un Work Order, sin importar su severidad.
- **El suscriptor abre la intervención por mensaje crítico (BR-205).** *Reversión documentada:* el diseño inicial dejaba que Laura abriera el Work Order con un botón; con US-205 lo abre el suscriptor automáticamente ante una crítica vigente (se avisó a Emiliano). La deduplicación es por identidad del mensaje: `WorkOrder.Message_Key__c = messageId`. Un reenvío (misma identidad, mismo contenido) reutiliza la intervención y la enlaza; una misma identidad con contenido distinto es un **conflicto** (`IDENTITY_CONFLICT`), no un aviso nuevo. Javier sigue siendo el único que avanza y cierra el Work Order.
- **Garantía frente a duplicados y concurrencia.** La unicidad de `Message_Key__c` es el candado: aunque el bus entregue en paralelo, no puede haber dos intervenciones para el mismo `messageId`; un choque concurrente (`DUPLICATE_VALUE`) se reconsulta y se reutiliza. Si la creación falla por otra razón, la señal **no** queda procesada satisfactoriamente: su log pasa a `Rejected`/`INTERVENTION_FAILED` con `Retry_Safe = true`. *Límite:* consolidar varias claves distintas del mismo activo en un único incidente es un extra fuera del alcance base.
- **La severidad la calcula `MeasurementSeverityClassifier` (BR-204/BR-206).** El procesador compara la lectura con los límites de `Measurement_Threshold__mdt` (aviso, crítico y dirección) y la severidad viaja en `TelemetrySignalOutcome.severity`; US-203 solo la guarda en `Asset_Condition__c`. Los valores de los límites son de ejemplo hasta que Emiliano entregue los reales; sin límites válidos la señal se rechaza con un motivo (`THRESHOLD_*`), nunca se asume `Normal`. La conectividad no es una medición: su fila queda en `Normal`.
- **El estado del activo es su peor lectura vigente (BR-206).** Un activo con varias mediciones se resume con la severidad más alta entre sus filas de `Asset_Condition__c` (Crítico > Advertencia > Normal). `OperatorStatusService` la calcula al consultar (no hay rollup guardado) y la devuelve en cada fila como `assetSeverity`, aunque Laura filtre por severidad. La lista va primero por ese estado y al final los activos sin lectura. La conectividad cuenta como `Normal`: una conexión perdida se muestra (*Conexión: Perdida*) pero no sube el estado; subirlo sería otra historia. La pantalla solo muestra la severidad guardada, nunca la recalcula.
- **El estado guarda el tipo de medición tal como llega del simulador.** La fila usa `WATER_PRESSURE`, `TEMPERATURE`, etc. (y `CONNECTIVITY` para la conectividad). La pantalla de Laura los traduce (*presión de agua*, *temperatura*, *consumo de agua*, *consumo de energía*, *conectividad*) junto con sus unidades; un código que no conoce lo muestra tal cual. Cada severidad se ve con icono y texto, no solo con color.
- **La ingesta corre en modo sistema.** Desde la API 67, Apex consulta en modo usuario por defecto. El suscriptor corre como *Automated Process*, así que el estado y los logs se leen y escriben con `SYSTEM_MODE` explícito. La seguridad por usuario (BR-208) se aplica en lo que consultan Laura, Javier y Camila.
- **Una sola sesión del simulador.** Cada `POST /session` es un escenario nuevo, así que solo se abre cuando no hay cursor o cuando la sesión vence (dura 30 días).
- **Ritmo de consulta.** El simulador sugiere esperar 10 segundos entre lotes, pero un Queueable no puede esperar menos de 1 minuto. Por eso el job se vuelve a encolar cada minuto.

## Lo que mostró el simulador

- **Hay duplicados.** `msg_000014` llegó dos veces, con `deliveryId` distintos (`dlv_000014` y `dlv_000018`) y el mismo `occurredAt`. Hoy se registran las dos entregas. La clave para detectar el duplicado es `messageId`, no `deliveryId`.
- **El reloj es simulado.** `occurredAt` puede quedar adelante de la hora real de Salesforce. Para saber si una señal llegó atrasada, hay que comparar `occurredAt` entre señales del mismo activo, no contra la hora de Salesforce.
