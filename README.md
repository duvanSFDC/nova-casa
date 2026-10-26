# Nova Casa

Proyecto Salesforce (SFDX, API 67) que recibe señales IoT de los edificios desde un simulador, las valida y las registra. Con cada señal válida actualiza el estado del equipo y, ante una lectura crítica, abre una intervención. Cada rol ve solo lo que le corresponde.

## Requisitos

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- Node.js 20+
- Acceso a la org `novacasa`

## Puesta en marcha

```bash
# 1. Dependencias de los LWC
npm install

# 2. Autenticar la org
sf org login web --alias novacasa

# 3. Desplegar la metadata
sf project deploy start --source-dir force-app --target-org novacasa
```

> El token del simulador **no** está en el repo: vive solo en la org, en la External Credential `Nova_Simulator`.

## Pruebas

```bash
# Apex: validación sin desplegar (compila y corre las pruebas)
sf project deploy validate --source-dir force-app --target-org novacasa --test-level RunLocalTests

# LWC: pruebas unitarias con Jest
npm run test:unit
```

En cada Pull Request, el CI (GitHub Actions) corre Jest y la validación Apex automáticamente.

## Estructura

```
force-app/main/default/   Metadata de Salesforce (Apex, LWC, objetos, flujos, permisos…)
docs/                     Documentación técnica y evidencias
scripts/                  Scripts de apoyo (Apex anónimo, utilidades)
```

## Flujo de trabajo

- `main` está protegida: los cambios entran por **Pull Request**.
- Una rama corta por tarea → PR → CI en verde → merge → se borra la rama.

## Documentación

La documentación técnica completa (modelo de datos, clases, seguridad, decisiones de diseño) se mantiene aparte, en `docs/documentacion-tecnica.md` y en el documento del equipo.
