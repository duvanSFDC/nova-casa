@IsTest
private class MeasurementLabelsTest {
    @IsTest
    static void traduceLosTiposYUnidadesQueEnviaElSimulador() {
        Assert.areEqual('temperatura', MeasurementLabels.typeLabel('TEMPERATURE'));
        Assert.areEqual('presión de agua', MeasurementLabels.typeLabel('water_pressure'));
        Assert.areEqual('consumo de energía', MeasurementLabels.typeLabel('ENERGY_CONSUMPTION'));
        Assert.areEqual('°C', MeasurementLabels.unitLabel('CELSIUS'));
        Assert.areEqual('kWh/15 min', MeasurementLabels.unitLabel('KWH_PER_15_MIN'));
        Assert.areEqual('L/15 min', MeasurementLabels.unitLabel('LITER_PER_15_MIN'));
    }

    @IsTest
    static void devuelveElCodigoCuandoNoHayTraduccion() {
        Assert.areEqual('HUMIDITY', MeasurementLabels.typeLabel('HUMIDITY'));
        Assert.areEqual('PERCENT', MeasurementLabels.unitLabel('PERCENT'));
        Assert.areEqual(null, MeasurementLabels.typeLabel(null));
        Assert.areEqual('', MeasurementLabels.unitLabel(''));
    }
}
