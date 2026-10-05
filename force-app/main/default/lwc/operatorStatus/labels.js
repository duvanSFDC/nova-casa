const SEVERITIES = {
    Normal: { label: 'Normal', icon: 'utility:success', cellClass: '' },
    Warning: { label: 'Advertencia', icon: 'utility:warning', cellClass: 'slds-text-title_bold' },
    Critical: { label: 'Crítico', icon: 'utility:error', cellClass: 'slds-text-color_error slds-text-title_bold' }
};

const TYPE_LABELS = {
    WATER_PRESSURE: 'presión de agua',
    TEMPERATURE: 'temperatura',
    WATER_CONSUMPTION: 'consumo de agua',
    ENERGY_CONSUMPTION: 'consumo de energía',
    CONNECTIVITY: 'conectividad'
};

const UNIT_LABELS = {
    BAR: 'bar',
    CELSIUS: '°C',
    LITER_PER_15_MIN: 'L/15 min',
    KWH_PER_15_MIN: 'kWh/15 min'
};

const COMMUNICATION_LABELS = {
    HEALTHY: 'OK',
    LOST: 'Perdida',
    RESTORED: 'Restablecida'
};

export const CONNECTIVITY = 'CONNECTIVITY';

export function severityCell(severity) {
    if (!severity) {
        return { label: '—', icon: undefined, cellClass: '' };
    }
    return SEVERITIES[severity] || { label: severity, icon: undefined, cellClass: '' };
}

export function typeLabel(code) {
    return TYPE_LABELS[code] || code;
}

export function unitLabel(code) {
    return UNIT_LABELS[code] || code;
}

export function communicationLabel(status) {
    if (!status) {
        return 'sin estado';
    }
    return COMMUNICATION_LABELS[status] || status;
}
