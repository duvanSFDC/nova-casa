import { createElement } from 'lwc';
import AlertThresholdEditor, { mergeDrafts, toDatatableErrors, toTableRow } from 'c/alertThresholdEditor';
import getThresholds from '@salesforce/apex/AlertThresholdController.getThresholds';
import saveLimits from '@salesforce/apex/AlertThresholdController.saveLimits';

jest.mock('@salesforce/apex/AlertThresholdController.getThresholds', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AlertThresholdController.saveLimits', () => ({ default: jest.fn() }), { virtual: true });

const PUMP = {
    id: 'a0X000000000001',
    name: 'Bomba de agua · presión de agua',
    unitLabel: 'bar',
    direction: 'Below',
    warningLimit: 1.5,
    criticalLimit: 1,
    lastModifiedAt: '2026-10-13T15:00:00.000Z',
    lastModifiedBy: 'Javier Coordinador',
    canEdit: true
};

const ROOM = {
    id: 'a0X000000000002',
    name: 'Cuarto técnico · temperatura',
    unitLabel: '°C',
    direction: 'Above',
    warningLimit: 30,
    criticalLimit: 35,
    lastModifiedAt: '2026-10-13T15:00:00.000Z',
    lastModifiedBy: 'Camila Administradora',
    canEdit: true
};

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(rows = [PUMP, ROOM]) {
    getThresholds.mockResolvedValue(rows);
    const element = createElement('c-alert-threshold-editor', { is: AlertThresholdEditor });
    document.body.appendChild(element);
    await flush();
    return element;
}

function table(element) {
    return element.shadowRoot.querySelector('lightning-datatable');
}

async function save(element, draftValues) {
    table(element).dispatchEvent(new CustomEvent('save', { detail: { draftValues } }));
    await flush();
    await flush();
}

describe('c-alert-threshold-editor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists the thresholds with readable names and editable limits', async () => {
        const element = await render();

        const datatable = table(element);
        expect(datatable.data).toHaveLength(2);
        expect(datatable.data[0].name).toBe('Bomba de agua · presión de agua');
        expect(datatable.data[0].directionLabel).toBe('al bajar');
        const editable = datatable.columns.filter((column) => column.editable).map((column) => column.fieldName);
        expect(editable).toEqual(['warningLimit', 'criticalLimit']);
    });

    it('is read only when the user cannot edit the limits', async () => {
        const element = await render([{ ...PUMP, canEdit: false }]);

        expect(table(element).columns.some((column) => column.editable)).toBe(false);
        expect(element.shadowRoot.querySelector('p[role="status"]').textContent).toContain('no cambiarlos');
    });

    it('sends both limits, keeping the one that was not touched', async () => {
        saveLimits.mockResolvedValue([]);
        const element = await render();

        await save(element, [{ id: PUMP.id, warningLimit: '1.8' }]);

        expect(saveLimits).toHaveBeenCalledWith({
            changes: [{ id: PUMP.id, warningLimit: 1.8, criticalLimit: 1 }]
        });
        expect(getThresholds).toHaveBeenCalledTimes(2);
        expect(table(element).errors).toBeUndefined();
    });

    it('marks the row that the server rejected and keeps its draft', async () => {
        saveLimits.mockResolvedValue([{ id: PUMP.id, message: 'El límite crítico tiene que ser más grave.' }]);
        const element = await render();

        await save(element, [
            { id: PUMP.id, criticalLimit: '2' },
            { id: ROOM.id, criticalLimit: '38' }
        ]);

        const datatable = table(element);
        expect(datatable.errors.rows[PUMP.id].messages).toEqual(['El límite crítico tiene que ser más grave.']);
        expect(datatable.errors.rows[ROOM.id]).toBeUndefined();
        expect(datatable.draftValues).toEqual([{ id: PUMP.id, criticalLimit: '2' }]);
    });

    it('shows a table error when saving is not allowed', async () => {
        saveLimits.mockRejectedValue({ body: { message: 'No tienes permiso para cambiar los umbrales.' } });
        const element = await render();

        await save(element, [{ id: PUMP.id, warningLimit: '1.8' }]);

        expect(table(element).errors.table.messages).toEqual(['No tienes permiso para cambiar los umbrales.']);
    });

    it('shows the server message and a retry when loading fails', async () => {
        getThresholds.mockRejectedValue({ body: { message: 'No pudimos consultar los umbrales.' } });
        const element = createElement('c-alert-threshold-editor', { is: AlertThresholdEditor });
        document.body.appendChild(element);
        await flush();

        const alert = element.shadowRoot.querySelector('div[role="alert"]');
        expect(alert.textContent).toContain('No pudimos consultar los umbrales.');
        expect(table(element)).toBeNull();
    });

    it('says when there are no thresholds', async () => {
        const element = await render([]);

        expect(element.shadowRoot.querySelector('p[role="status"]').textContent).toBe('No hay umbrales configurados.');
    });
});

describe('helpers', () => {
    it('turns an emptied cell into null so the server rejects it', () => {
        expect(mergeDrafts([toTableRow(PUMP)], [{ id: PUMP.id, warningLimit: '' }])).toEqual([
            { id: PUMP.id, warningLimit: null, criticalLimit: 1 }
        ]);
    });

    it('names the threshold in the error summary', () => {
        const errors = toDatatableErrors([{ id: ROOM.id, message: 'Faltan datos.' }], [toTableRow(ROOM)]);
        expect(errors.table.title).toBe('Un umbral no se guardó');
        expect(errors.table.messages).toEqual(['Cuarto técnico · temperatura: Faltan datos.']);
    });

    it('shows when and who changed the threshold last', () => {
        expect(toTableRow(PUMP).lastChangeLabel).toContain('Javier Coordinador');
    });
});
