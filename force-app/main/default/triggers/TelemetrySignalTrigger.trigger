trigger TelemetrySignalTrigger on Telemetry_Signal__e(after insert) {
    TelemetrySignalSubscriber.handle(Trigger.new);
}
