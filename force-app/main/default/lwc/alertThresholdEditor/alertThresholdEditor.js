import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getThresholds from '@salesforce/apex/AlertThresholdController.getThresholds';
import saveLimits from '@salesforce/apex/AlertThresholdController.saveLimits';

const DIRECTION_LABELS = {
    Below: 'al bajar',
    Above: 'al subir'
};

const LIMIT_TYPE_ATTRIBUTES = { step: '0.0001', maximumFractionDigits: 4 };

const DATE_FORMAT = new Intl.DateTimeFormat('es', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: TIME_ZONE
});

function buildColumns(editable) {
    return [
        { label: 'Equipo y medición', fieldName: 'name' },
        { label: 'Unidad', fieldName: 'unitLabel', initialWidth: 120 },
        { label: 'Empeora', fieldName: 'directionLabel', initialWidth: 120 },
        {
            label: 'Advertencia desde',
            fieldName: 'warningLimit',
            type: 'number',
            editable,
            typeAttributes: LIMIT_TYPE_ATTRIBUTES
        },
        {
            label: 'Crítico desde',
            fieldName: 'criticalLimit',
            type: 'number',
            editable,
            typeAttributes: LIMIT_TYPE_ATTRIBUTES
        },
        { label: 'Último cambio', fieldName: 'lastChangeLabel' }
    ];
}

export default class AlertThresholdEditor extends LightningElement {
    state = 'loading';
    rows = [];
    columns = buildColumns(false);
    draftValues = [];
    errors;
    isSaving = false;
    canEdit = false;
    errorMessage = 'No pudimos consultar los umbrales.';

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

    get isReadOnly() {
        return this.isData && !this.canEdit;
    }

    handleRefresh() {
        this.draftValues = [];
        this.errors = undefined;
        this.load();
    }

    handleCancel() {
        this.draftValues = [];
        this.errors = undefined;
    }

    async load() {
        this.state = 'loading';
        try {
            const result = (await getThresholds()) || [];
            this.canEdit = result.length > 0 && result.every((row) => row.canEdit);
            this.columns = buildColumns(this.canEdit);
            this.rows = result.map(toTableRow);
            this.state = this.rows.length ? 'data' : 'empty';
        } catch (error) {
            this.rows = [];
            this.errorMessage = error?.body?.message || 'No pudimos consultar los umbrales.';
            this.state = 'error';
        }
    }

    async handleSave(event) {
        const drafts = event.detail.draftValues || [];
        const changes = mergeDrafts(this.rows, drafts);
        this.isSaving = true;
        try {
            const saveErrors = (await saveLimits({ changes })) || [];
            if (saveErrors.length) {
                this.errors = toDatatableErrors(saveErrors, this.rows);
                const failed = new Set(saveErrors.map((error) => error.id));
                this.draftValues = drafts.filter((draft) => failed.has(draft.id));
                if (saveErrors.length < changes.length) {
                    await this.reloadKeepingDrafts();
                }
                return;
            }
            this.errors = undefined;
            this.draftValues = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Umbrales guardados',
                    message: 'Las próximas señales se califican con los límites nuevos.',
                    variant: 'success'
                })
            );
            await this.load();
        } catch (error) {
            this.errors = {
                table: {
                    title: 'No se guardó ningún cambio',
                    messages: [error?.body?.message || 'No pudimos guardar los umbrales.']
                }
            };
        } finally {
            this.isSaving = false;
        }
    }

    async reloadKeepingDrafts() {
        const result = (await getThresholds()) || [];
        this.rows = result.map(toTableRow);
    }
}

export function toTableRow(row) {
    return {
        id: row.id,
        name: row.name,
        unitLabel: row.unitLabel || '—',
        directionLabel: DIRECTION_LABELS[row.direction] || '—',
        warningLimit: row.warningLimit,
        criticalLimit: row.criticalLimit,
        lastChangeLabel: lastChangeLabel(row)
    };
}

/** El servidor recibe siempre los dos límites: el que no se tocó va con su valor actual. */
export function mergeDrafts(rows, drafts) {
    const byId = new Map(rows.map((row) => [row.id, row]));
    return drafts.map((draft) => {
        const current = byId.get(draft.id) || {};
        return {
            id: draft.id,
            warningLimit: toNumber('warningLimit' in draft ? draft.warningLimit : current.warningLimit),
            criticalLimit: toNumber('criticalLimit' in draft ? draft.criticalLimit : current.criticalLimit)
        };
    });
}

export function toDatatableErrors(saveErrors, rows) {
    const names = new Map(rows.map((row) => [row.id, row.name]));
    const rowErrors = {};
    for (const error of saveErrors) {
        rowErrors[error.id] = {
            title: `No se guardó ${names.get(error.id) || 'este umbral'}`,
            messages: [error.message],
            fieldNames: ['warningLimit', 'criticalLimit']
        };
    }
    return {
        rows: rowErrors,
        table: {
            title: saveErrors.length === 1 ? 'Un umbral no se guardó' : `${saveErrors.length} umbrales no se guardaron`,
            messages: saveErrors.map((error) => `${names.get(error.id) || error.id}: ${error.message}`)
        }
    };
}

function toNumber(value) {
    if (value === '' || value === null || value === undefined) {
        return null;
    }
    return Number(value);
}

function lastChangeLabel(row) {
    if (!row.lastModifiedAt) {
        return '—';
    }
    const when = DATE_FORMAT.format(new Date(row.lastModifiedAt));
    return row.lastModifiedBy ? `${when} · ${row.lastModifiedBy}` : when;
}
