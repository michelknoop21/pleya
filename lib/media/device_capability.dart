/// One capability value plus where it came from.
///
/// Not to be confused with `ServerCapabilities` in this same directory. That
/// one says which affordances the UI may show for a *backend*; this one is a
/// building block of `DeviceCapabilities`, which says what *this device* can
/// actually play. Both end up in the playback path, so every file in the
/// `device_` family opens with this distinction.
library;

/// How sure the observation is. Says nothing about who decided.
///
/// [detected] means something was measured or read back from the system.
/// [inferred] means it follows from the player engine or the platform without
/// having been asked. [unknown] means nobody knows, and the planner in PS-6
/// has to pick the safe side per property rather than one generic default.
enum CapabilityConfidence { detected, inferred, unknown }

/// A single capability value, its confidence, and the observation it may be
/// overriding.
///
/// [value] is the effective answer. [observed] carries what detection said
/// when a user override replaced it, so the reason stays explainable ("stereo
/// because you set it that way"). [confidence] describes the *observation*,
/// never the override: overriding an inferred decoder list does not turn that
/// list into a measurement, so an override reports the confidence of the thing
/// underneath it.
class Capability<T> {
  /// [_observationConfidence] is only consulted when [observed] is null. An
  /// override carries its confidence in the capability it wraps, which is what
  /// keeps `inferred` from silently becoming `detected`.
  const Capability._(this.value, this._observationConfidence, this.observed);

  /// Measured or read back from the system.
  const Capability.detected(T value) : this._(value, CapabilityConfidence.detected, null);

  /// Follows from the player engine or the platform, but was not asked.
  const Capability.inferred(T value) : this._(value, CapabilityConfidence.inferred, null);

  /// Nobody knows. Consumers must keep whatever they do today.
  const Capability.unknown() : this._(null, CapabilityConfidence.unknown, null);

  /// The user replaced [observed] with [value].
  const Capability.overridden(T value, {required Capability<T> observed})
    : this._(value, CapabilityConfidence.unknown, observed);

  /// The effective answer, or null when nothing is known.
  final T? value;

  final CapabilityConfidence _observationConfidence;

  /// What detection said before the override. Null when this is not an
  /// override.
  final Capability<T>? observed;

  /// The confidence of the underlying observation, following the chain down
  /// through nested overrides.
  CapabilityConfidence get confidence => observed?.confidence ?? _observationConfidence;

  /// The value detection produced, which differs from [value] exactly when the
  /// user overrode it.
  T? get observedValue => observed?.value;

  bool get isOverride => observed != null;

  /// True when there is an effective answer to act on. An [unknown] capability
  /// is false; so is an override that deliberately clears a value.
  bool get isKnown => value != null;

  /// Applies a user override, keeping the current capability as the
  /// observation. Overriding an override collapses to a single level, so the
  /// original detection stays reachable instead of being buried.
  Capability<T> overriddenWith(T newValue) => Capability<T>.overridden(newValue, observed: observed ?? this);

  /// One-line form for the startup log and for `DeviceCapabilities.describe()`.
  String describe() {
    final base = value == null ? '?' : _describeValue(value as T);
    if (!isOverride) return '$base(${confidence.name})';
    final was = observedValue == null ? '?' : _describeValue(observedValue as T);
    return '$base(override of $was/${confidence.name})';
  }

  static String _describeValue(Object? value) {
    if (value is Iterable) return value.join(',');
    return '$value';
  }

  @override
  String toString() => 'Capability<$T>(${describe()})';
}
