import { LightningElement } from 'lwc';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getAssets from '@salesforce/apex/OperatorStatusService.getAssets';
import getBuildings from '@salesforce/apex/OperatorStatusService.getBuildings';
import { CONNECTIVITY, communicationLabel, severityCell, typeLabel, unitLabel } from './labels';

const COLUMNS = [
    {
        label: 'Activo',
        fieldName: 'assetUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'assetName' },
            target: '_self',
            tooltip: 'Abrir el activo'
        }
    },
    { label: 'Edificio', fieldName: 'buildingName' },
    {
        label: 'Estado del activo',
        fieldName: 'assetSeverityLabel',
        cellAttributes: {
            iconName: { fieldName: 'assetSeverityIcon' },
            iconAlternativeText: { fieldName: 'assetSeverityLabel' },
            class: { fieldName: 'assetSeverityClass' }
        }
    },
    { label: 'Lectura', fieldName: 'readingLabel' },
    {
        label: 'Severidad',
        fieldName: 'severityLabel',
        cellAttributes: {
            iconName: { fieldName: 'severityIcon' },
            iconAlternativeText: { fieldName: 'severityLabel' },
            class: { fieldName: 'severityClass' }
        }
    },
    { label: 'Hora de origen', fieldName: 'occurredAtLabel' },
    {
        label: 'Intervención',
        fieldName: 'workOrderUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'workOrderLabel' },
            target: '_self'
        }
    }
];

const SEVERITY_OPTIONS = [
    { label: 'Todas', value: '' },
    { label: 'Normal', value: 'Normal' },
    { label: 'Advertencia', value: 'Warning' },
    { label: 'Crítico', value: 'Critical' }
];

const DATE_FORMAT = new Intl.DateTimeFormat('es', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZone: TIME_ZONE
});

export default class OperatorStatus extends LightningElement {
    columns = COLUMNS;
    severityOptions = SEVERITY_OPTIONS;
    buildingOptions = [{ label: 'Todos los edificios', value: '' }];
    buildingId = '';
    severity = '';
    state = 'loading';
    tableRows = [];
    consultedAtLabel = '';
    errorMessage = 'No pudimos consultar los equipos.';

    connectedCallback() {
        this.load();
    }

    get isLoading() {
        return this.state === 'loading';
    }

    get isData() {
        return this.state === 'data';
    }

    get isEmpty() {
        return this.state === 'empty';
    }

    get isError() {
        return this.state === 'error';
    }

    get showConsultedAt() {
        return this.state === 'data' || this.state === 'empty';
    }

    get hasActiveFilters() {
        return Boolean(this.buildingId || this.severity);
    }

    get isFilterEmpty() {
        return this.isEmpty && this.hasActiveFilters;
    }

    get isNoAssets() {
        return this.isEmpty && !this.hasActiveFilters;
    }

    get clearDisabled() {
        return this.isLoading || !this.hasActiveFilters;
    }

    handleRefresh() {
        this.load();
    }

    handleBuildingChange(event) {
        this.buildingId = event.detail.value || '';
        this.load();
    }

    handleSeverityChange(event) {
        this.severity = event.detail.value || '';
        this.load();
    }

    handleClearFilters() {
        this.buildingId = '';
        this.severity = '';
        this.load();
    }

    async load() {
        this.state = 'loading';
        try {
            const [buildings, result] = await Promise.all([
                getBuildings(),
                getAssets({
                    buildingId: this.buildingId || null,
                    severity: this.severity || null
                })
            ]);
            this.buildingOptions = [
                { label: 'Todos los edificios', value: '' },
                ...(buildings || []).map((building) => ({
                    label: building.buildingName,
                    value: building.buildingId
                }))
            ];
            const rows = result.rows || [];
            this.consultedAtLabel = formatWhen(result.consultedAt);
            this.tableRows = rows.map(toTableRow);
            this.state = this.tableRows.length ? 'data' : 'empty';
        } catch (error) {
            this.tableRows = [];
            this.state = 'error';
        }
    }
}

export function toTableRow(row) {
    const assetSeverity = severityCell(row.assetSeverity);
    const base = {
        rowKey: row.rowKey,
        assetName: row.assetName,
        assetUrl: recordUrl('Asset', row.assetId),
        buildingName: row.buildingName || '—',
        assetSeverityLabel: assetSeverity.label,
        assetSeverityIcon: assetSeverity.icon,
        assetSeverityClass: assetSeverity.cellClass,
        workOrderUrl: row.workOrderId ? recordUrl('WorkOrder', row.workOrderId) : undefined,
        workOrderLabel: row.workOrderNumber || '—'
    };
    if (!row.hasReading) {
        return {
            ...base,
            readingLabel: 'Sin lectura',
            severityLabel: '—',
            occurredAtLabel: '—'
        };
    }
    const severity = severityCell(row.severity);
    return {
        ...base,
        readingLabel: readingLabel(row),
        severityLabel: severity.label,
        severityIcon: severity.icon,
        severityClass: severity.cellClass,
        occurredAtLabel: formatWhen(row.occurredAt)
    };
}

function readingLabel(row) {
    if (row.measurementType === CONNECTIVITY) {
        return `Conexión: ${communicationLabel(row.communicationStatus)}`;
    }
    const unit = row.measurementUnit ? ` ${unitLabel(row.measurementUnit)}` : '';
    return `${formatValue(row.measurementValue)}${unit} · ${typeLabel(row.measurementType)}`;
}

function recordUrl(objectApiName, recordId) {
    return `/lightning/r/${objectApiName}/${recordId}/view`;
}

function formatValue(value) {
    if (value === null || value === undefined) {
        return '—';
    }
    return String(Number(value));
}

function formatWhen(value) {
    if (!value) {
        return '—';
    }
    return DATE_FORMAT.format(new Date(value));
}