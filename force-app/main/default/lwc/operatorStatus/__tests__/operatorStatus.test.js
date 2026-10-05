import { createElement } from 'lwc';
import OperatorStatus from 'c/operatorStatus';
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

async function render() {
    getBuildings.mockResolvedValue([]);
    getAssets.mockResolvedValue({ consultedAt: '2026-10-05T15:01:00.000Z', rows: ROWS });
    const element = createElement('c-operator-status', { is: OperatorStatus });
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
});
