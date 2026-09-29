/**
 * Cliente HTTP del simulador de Nova Casa.
 * El token vive en la Named Credential Nova_Simulator; esta clase nunca lo ve.
 */
public inherited sharing class NovaSimulatorClient {
    public static final String NAMED_CREDENTIAL = 'callout:Nova_Simulator';
    public static final String CURSOR_HEADER = 'X-Simulator-Cursor';
    private static final Integer TIMEOUT_MS = 20000;

    public class SimulatorException extends Exception {
    }

    public class Session {
        public String cursor;
        public Datetime startedAt;
        public Datetime expiresAt;
    }

    public class TelemetryPage {
        public List<Map<String, Object>> items = new List<Map<String, Object>>();
        public String nextCursor;
        public Boolean hasMore = false;
        public Integer pollAfterMs;
    }

    public Session startSession() {
        Map<String, Object> body = parseObject(send('POST', '/session', null, '{}'));

        Session session = new Session();
        session.cursor = (String) body.get('cursor');
        Map<String, Object> info = (Map<String, Object>) body.get('session');
        if (info != null) {
            session.startedAt = TelemetrySignalMapper.parseDatetime(info.get('startedAt'));
            session.expiresAt = TelemetrySignalMapper.parseDatetime(info.get('expiresAt'));
        }
        if (String.isBlank(session.cursor)) {
            throw new SimulatorException('POST /session no devolvió cursor.');
        }
        return session;
    }

    public TelemetryPage fetchTelemetry(String cursor, Integer batchSize) {
        Map<String, Object> body = parseObject(send('GET', '/telemetry?limit=' + batchSize, cursor, null));

        TelemetryPage page = new TelemetryPage();
        List<Object> data = (List<Object>) body.get('data');
        if (data != null) {
            for (Object item : data) {
                page.items.add((Map<String, Object>) item);
            }
        }
        Map<String, Object> pagination = (Map<String, Object>) body.get('pagination');
        if (pagination != null) {
            page.nextCursor = (String) pagination.get('nextCursor');
            page.hasMore = pagination.get('hasMore') == true;
            Object poll = pagination.get('pollAfterMs');
            page.pollAfterMs = poll == null ? null : Integer.valueOf(poll);
        }
        return page;
    }

    private HttpResponse send(String method, String path, String cursor, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod(method);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');
        if (cursor != null) {
            req.setHeader(CURSOR_HEADER, cursor);
        }
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }

        HttpResponse res = new Http().send(req);
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new SimulatorException(method + ' ' + path + ' respondió ' + status + ': ' + describe(res.getBody()));
        }
        return res;
    }

    private static Map<String, Object> parseObject(HttpResponse res) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new SimulatorException('Respuesta no es JSON: ' + describe(res.getBody()));
        }
    }

    private static String describe(String body) {
        if (String.isBlank(body)) {
            return '(sin cuerpo)';
        }
        try {
            Map<String, Object> problem = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (problem.get('detail') != null) {
                return String.valueOf(problem.get('detail'));
            }
        } catch (Exception e) {
            // El cuerpo no es un problem+json; se devuelve recortado.
        }
        return body.left(200);
    }
}
