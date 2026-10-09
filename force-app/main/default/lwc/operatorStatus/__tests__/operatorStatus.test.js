import { createElement } from 'lwc';
import OperatorStatus, { computeSummary, isUrgentAsset } from 'c/operatorStatus';
import getAssets from '@salesforce/apex/OperatorStatusService.getAssets';
import getBuildings from '@salesforce/apex/OperatorStatusService.getBuildings';

jest.mock('@salesforce/apex/OperatorStatusService.getAssets', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OperatorStatusService.getBuildings', () => ({ default: jest.fn() }), { virtual: true });

const ROWS = [
    {
        rowKey: 'c1',
        assetId: '02i000000000001',
        assetName: 'Bomba',
        buildingName: 'Norte',
        hasReading: true,
        measurementType: 'WATER_PRESSURE',
        measurementValue: 0.9,
        measurementUnit: 'BAR',
        severity: 'Critical',
        assetSeverity: 'Critical',
        occurredAt: '2026-10-05T15:00:00.000Z',
        workOrderId: '0WO000000000001',
        workOrderNumber: '00000002'
    },
    {
        rowKey: 'c2',
        assetId: '02i000000000001',
        assetName: 'Bomba',
        buildingName: 'Norte',
        hasReading: true,
        measurementType: 'TEMPERATURE',
        measurementValue: 31,
        measurementUnit: 'CELSIUS',
        severity: 'Warning',
        assetSeverity: 'Critical',
        occurredAt: '2026-10-05T15:00:00.000Z'
    },
    {
        rowKey: 'c3',
        assetId: '02i000000000002',
        assetName: 'Cámara',
        buildingName: 'Sur',
        hasReading: true,
        measurementType: 'CONNECTIVITY',
        communicationStatus: 'LOST',
        severity: 'Normal',
        assetSeverity: 'Normal',
        occurredAt: '2026-10-05T15:00:00.000Z'
    },
    {
        rowKey: 'c4',
        assetId: '02i000000000003',
        assetName: 'Sensor nuevo',
        buildingName: 'Sur',
        hasReading: true,
        measurementType: 'HUMIDITY',
        measurementValue: 40,
        measurementUnit: 'PERCENT',
        severity: 'Normal',
        assetSeverity: 'Normal',
        occurredAt: '2026-10-05T15:00:00.000Z'
    },
    {
        rowKey: '02i000000000004:none',
        assetId: '02i000000000004',
        assetName: 'Luz',
        buildingName: 'Sur',
        hasReading: false
    }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(props = {}) {
    getBuildings.mockResolvedValue([]);
    getAssets.mockResolvedValue({ consultedAt: '2026-10-05T15:01:00.000Z', rows: ROWS });
    const element = createElement('c-operator-status', { is: OperatorStatus });
    Object.assign(element, props);
    document.body.appendChild(element);
    await flush();
    return element;
}

function tableRows(element) {
    return element.shadowRoot.querySelector('lightning-datatable').data;
}

describe('c-operator-status', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the asset state next to the reading severity, with text and icon', async () => {
        const element = await render();
        const columns = element.shadowRoot.querySelector('lightning-datatable').columns;
        const labels = columns.map((column) => column.label);
        expect(labels.indexOf('Estado del activo')).toBeGreaterThan(-1);
        expect(labels.indexOf('Estado del activo')).toBeLessThan(labels.indexOf('Lectura'));

        const [pressure, temperature] = tableRows(element);
        expect(pressure).toMatchObject({
            assetSeverityLabel: 'Crítico',
            assetSeverityIcon: 'utility:error',
            severityLabel: 'Crítico',
            readingLabel: '0.9 bar · presión de agua',
            workOrderLabel: '00000002'
        });
        expect(temperature).toMatchObject({
            assetSeverityLabel: 'Crítico',
            severityLabel: 'Advertencia',
            severityIcon: 'utility:warning',
            readingLabel: '31 °C · temperatura',
            workOrderLabel: '—'
        });
    });

    it('shows the communication status on a connectivity row without raising it', async () => {
        const element = await render();
        const camera = tableRows(element)[2];
        expect(camera.readingLabel).toBe('Conexión: Perdida');
        expect(camera.assetSeverityLabel).toBe('Normal');
        expect(camera.severityLabel).toBe('Normal');
    });

    it('shows an unknown measurement as it arrives', async () => {
        const element = await render();
        expect(tableRows(element)[3].readingLabel).toBe('40 PERCENT · HUMIDITY');
    });

    it('keeps the order the service returns and leaves an asset without reading last', async () => {
        const element = await render();
        const rows = tableRows(element);
        expect(rows.map((row) => row.rowKey)).toEqual(ROWS.map((row) => row.rowKey));
        expect(rows[4]).toMatchObject({
            readingLabel: 'Sin lectura',
            assetSeverityLabel: '—',
            severityLabel: '—'
        });
        expect(rows[4].assetSeverityIcon).toBeUndefined();
    });

    it('en el inicio enfocado (urgentOnly) muestra solo activos críticos o en advertencia y oculta los filtros', async () => {
        const element = await render({ urgentOnly: true });
        const rows = tableRows(element);
        expect(rows.map((row) => row.rowKey)).toEqual(['c1', 'c2']);
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    });

    it('con showSummary muestra los contadores sobre el total, no sobre la vista filtrada', async () => {
        const element = await render({ urgentOnly: true, showSummary: true });
        const headings = Array.from(
            element.shadowRoot.querySelectorAll('.slds-text-heading_large')
        ).map((node) => node.textContent.trim());
        // Críticos = 1 (un activo), Advertencias = 0, Sin lectura = 1 (sobre los 4 activos del total)
        expect(headings).toEqual(['1', '0', '1']);
    });
});

describe('computeSummary', () => {
    it('cuenta activos (no filas) por estado y las filas sin lectura', () => {
        expect(computeSummary(ROWS)).toEqual({ criticals: 1, warnings: 0, noReading: 1 });
    });

    it('no duplica un activo con varias lecturas', () => {
        const summary = computeSummary([
            { assetId: 'a', assetSeverity: 'Warning', hasReading: true },
            { assetId: 'a', assetSeverity: 'Warning', hasReading: true },
            { assetId: 'b', assetSeverity: 'Critical', hasReading: true }
        ]);
        expect(summary).toEqual({ criticals: 1, warnings: 1, noReading: 0 });
    });

    it('con una lista vacía devuelve ceros', () => {
        expect(computeSummary([])).toEqual({ criticals: 0, warnings: 0, noReading: 0 });
    });
});

describe('isUrgentAsset', () => {
    it('es urgente cuando el activo está en crítico o advertencia', () => {
        expect(isUrgentAsset({ assetSeverity: 'Critical' })).toBe(true);
        expect(isUrgentAsset({ assetSeverity: 'Warning' })).toBe(true);
    });

    it('no es urgente cuando el activo está normal o sin estado', () => {
        expect(isUrgentAsset({ assetSeverity: 'Normal' })).toBe(false);
        expect(isUrgentAsset({})).toBe(false);
    });
});
