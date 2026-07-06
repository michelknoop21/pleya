class DonationService {
  // Supply your own via --dart-define=DONATION_URL=... ; empty keeps the
  // donation option hidden so funds are never routed to a third party.
  static const String donationUrl = String.fromEnvironment('DONATION_URL');

  static bool get isEnabled {
    return const bool.fromEnvironment('ENABLE_DONATIONS', defaultValue: false) && donationUrl.isNotEmpty;
  }
}
