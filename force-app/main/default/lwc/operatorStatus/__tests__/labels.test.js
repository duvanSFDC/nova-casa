import { communicationLabel, severityCell, typeLabel, unitLabel } from '../labels';

describe('operatorStatus labels', () => {
    it.each([
        ['WATER_PRESSURE', 'presión de agua'],
        ['TEMPERATURE', 'temperatura'],
        ['WATER_CONSUMPTION', 'consumo de agua'],
        ['ENERGY_CONSUMPTION', 'consumo de energía'],
        ['CONNECTIVITY', 'conectividad']
    ])('names the measurement type %s', (code, label) => {
        expect(typeLabel(code)).toBe(label);
    });

    it('shows an unknown measurement type or unit as it arrives', () => {
        expect(typeLabel('HUMIDITY')).toBe('HUMIDITY');
        expect(unitLabel('PERCENT')).toBe('PERCENT');
    });

    it('names the units the simulator sends', () => {
        expect(unitLabel('BAR')).toBe('bar');
        expect(unitLabel('CELSIUS')).toBe('°C');
        expect(unitLabel('LITER_PER_15_MIN')).toBe('L/15 min');
        expect(unitLabel('KWH_PER_15_MIN')).toBe('kWh/15 min');
    });

    it('gives every severity a text and an icon, and marks critical in red', () => {
        expect(severityCell('Normal')).toEqual({ label: 'Normal', icon: 'utility:success', cellClass: '' });
        expect(severityCell('Warning')).toMatchObject({ label: 'Advertencia', icon: 'utility:warning' });
        expect(severityCell('Critical')).toMatchObject({ label: 'Crítico', icon: 'utility:error' });
        expect(severityCell('Critical').cellClass).toContain('slds-text-color_error');
        expect(severityCell('Warning').cellClass).not.toContain('slds-text-color_error');
    });

    it('shows a dash without severity and the raw value for an unknown one', () => {
        expect(severityCell(null)).toEqual({ label: '—', icon: undefined, cellClass: '' });
        expect(severityCell('Urgent')).toEqual({ label: 'Urgent', icon: undefined, cellClass: '' });
    });

    it('names the communication status', () => {
        expect(communicationLabel('HEALTHY')).toBe('OK');
        expect(communicationLabel('LOST')).toBe('Perdida');
        expect(communicationLabel('RESTORED')).toBe('Restablecida');
        expect(communicationLabel(null)).toBe('sin estado');
        expect(communicationLabel('DEGRADED')).toBe('DEGRADED');
    });
});
