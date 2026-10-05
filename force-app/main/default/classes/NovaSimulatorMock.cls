@IsTest
public class NovaSimulatorMock implements HttpCalloutMock {
    public static final String SESSION_CURSOR = 'cursor-session-1';
    public static final String NEXT_CURSOR = 'cursor-next-2';

    public Integer sessionCalls = 0;
    public Integer telemetryCalls = 0;
    public String lastCursor;
    public String lastSessionBody;
    public Integer telemetryStatus = 200;
    public Integer healthStatus = 200;

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String endpoint = req.getEndpoint();

        if (endpoint.endsWith('/session')) {
            sessionCalls++;
            lastSessionBody = req.getBody();
            res.setStatusCode(201);
            res.setBody(sessionBody());
        } else if (endpoint.endsWith('/health')) {
            res.setStatusCode(healthStatus);
            res.setBody('{"status":"ok"}');
        } else if (endpoint.endsWith('/catalog')) {
            res.setStatusCode(200);
            res.setBody(catalogBody());
        } else if (endpoint.contains('/telemetry')) {
            telemetryCalls++;
            lastCursor = req.getHeader(NovaSimulatorClient.CURSOR_HEADER);
            res.setStatusCode(telemetryStatus);
            res.setBody(telemetryStatus == 200 ? telemetryBody() : problemBody());
        } else {
            res.setStatusCode(404);
            res.setBody('<html>not found</html>');
        }
        return res;
    }

    private static String sessionBody() {
        return JSON.serialize(
            new Map<String, Object>{
                'cursor' => SESSION_CURSOR,
                'session' => new Map<String, Object>{
                    'scenario' => 'MIXED',
                    'startedAt' => '2026-09-29T04:00:47.356Z',
                    'expiresAt' => '2099-10-29T04:00:47.356Z'
                }
            }
        );
    }

    private static String telemetryBody() {
        return JSON.serialize(
            new Map<String, Object>{
                'schemaVersion' => '1.0',
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'deliveryId' => 'dlv_000002',
                        'messageId' => 'msg_000002',
                        'messageType' => 'MEASUREMENT',
                        'source' => 'nova-casa-simulator',
                        'building' => new Map<String, Object>{ 'id' => 'BLD-BAQ-001', 'name' => 'Edificio Nova Caribe', 'city' => 'Barranquilla' },
                        'asset' => new Map<String, Object>{ 'id' => 'AST-BAQ-WATER-001', 'name' => 'Medidor de agua torre única', 'type' => 'WATER_METER' },
                        'sensorId' => 'SNS-BAQ-WATER-001',
                        'measurement' => new Map<String, Object>{ 'type' => 'WATER_CONSUMPTION', 'value' => 600, 'unit' => 'LITER_PER_15_MIN' },
                        'occurredAt' => '2026-09-29T03:45:51.211Z',
                        'publishedAt' => '2026-09-29T04:02:51.211Z'
                    },
                    new Map<String, Object>{
                        'deliveryId' => 'dlv_000003',
                        'messageId' => 'msg_000003',
                        'messageType' => 'CONNECTIVITY',
                        'source' => 'nova-casa-simulator',
                        'building' => new Map<String, Object>{ 'id' => 'BLD-BAQ-001', 'name' => 'Edificio Nova Caribe', 'city' => 'Barranquilla' },
                        'asset' => new Map<String, Object>{ 'id' => 'AST-BAQ-CAM-001', 'name' => 'Cámara azotea', 'type' => 'SECURITY_CAMERA' },
                        'sensorId' => 'SNS-BAQ-CAM-001',
                        'communication' => new Map<String, Object>{
                            'status' => 'HEALTHY',
                            'gapSeconds' => 60,
                            'lastSeenAt' => '2026-09-29T04:02:51.096Z',
                            'episodeId' => 'EPI-BAQ-hb'
                        },
                        'occurredAt' => '2026-09-29T04:03:49.222Z',
                        'publishedAt' => '2026-09-29T04:03:50.000Z'
                    }
                },
                'pagination' => new Map<String, Object>{ 'nextCursor' => NEXT_CURSOR, 'hasMore' => true, 'pollAfterMs' => 10000 }
            }
        );
    }

    private static String catalogBody() {
        return JSON.serialize(
            new Map<String, Object>{
                'contractVersion' => '1',
                'scenarios' => new List<String>{
                    'MIXED', 'QA_200', 'BOUNDARIES', 'CRITICAL_BURST', 'LATE_MESSAGES',
                    'DUPLICATES', 'CONFLICT', 'INVALID_DATA', 'CAMERA_OUTAGE'
                },
                'catalog' => new Map<String, Object>{
                    'buildings' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'BLD-BOG-001', 'name' => 'Edificio Nova Alameda', 'city' => 'Bogotá' },
                        new Map<String, Object>{ 'id' => 'BLD-BAQ-001', 'name' => 'Edificio Nova Caribe', 'city' => 'Barranquilla' }
                    }
                },
                'thresholdsReference' => new Map<String, Object>{
                    'measurements' => new Map<String, Object>{
                        'WATER_PRESSURE' => new Map<String, Object>{ 'unit' => 'BAR', 'normal' => new Map<String, Object>{ 'min' => 2.5, 'max' => 4 } }
                    }
                }
            }
        );
    }

    private static String problemBody() {
        return '{"title":"No autorizado","status":401,"detail":"Token inválido."}';
    }
}
