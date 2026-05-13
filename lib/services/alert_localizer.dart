/// English copy for the alert event_types the
/// `pushAlertNotificationtoUser` Lambda emits. The Lambda's defaults are
/// fine, but historical records sometimes have older or mixed-language
/// titles — this helper gives us a single source of truth so the mobile
/// app surfaces consistent English in both the FCM listener (new events)
/// and the alert provider's `_load` / `hydrateFromAws` (stored records).
///
/// Two entry points:
///  - [localizeAlert] when we already know the FCM event_type (used by
///    the foreground listener in main.dart).
///  - [reskinAlert] when we only have a stored title/body and need to
///    detect what kind of event it was, e.g. a record hydrated from
///    `user_alerts` that pre-dates the current copy.
library;

typedef LocalizedAlert = ({String title, String body});

LocalizedAlert? localizeAlert(String eventType, String fallbackBody) {
  switch (eventType) {
    case 'earthquake':
      return (
        title: '⚠️ Earthquake Alert',
        body: 'Tremor detected. Please move to a safe location.',
      );
    case 'gas_leak':
      return (
        title: '🚨 Gas Leak',
        body:
            'High gas levels detected. Please ventilate the home immediately.',
      );
    case 'rfid_unauthorized':
    case 'rfid_denied':
    case 'unauthorized_access':
      return (
        title: '🔒 Unauthorized Access Attempt',
        body: 'An unrecognized RFID card was detected at the door.',
      );
    case 'rfid_authorized':
      return (
        title: '✅ Door Unlocked',
        body: fallbackBody, // server fills {message} with the user name
      );
    case 'stove_left_on':
      return (
        title: '🔥 Stove Left On',
        body:
            'The stove is on while nobody is home. Please check on it.',
      );
    case 'tv_idle_long':
      return (
        title: '📺 TV Left On',
        body:
            'The TV has been idle for a while. Turn it off automatically?',
      );
    case 'ac_running_window_open':
      return (
        title: '❄️ AC Running, Window Open',
        body:
            'The AC is running with a window open. Check to save energy.',
      );
    case 'emotion_change':
      return (
        title: '🧠 Mood Change',
        body: fallbackBody, // server fills {message} with the detected mood
      );
    case 'device_offline':
      return (
        title: '📡 Device Offline',
        body: fallbackBody,
      );
  }
  return null;
}

/// Best-effort upgrade for *stored* alerts (local SharedPreferences and
/// AWS `user_alerts` rows) that were written with older or inconsistent
/// copy. Inspects the [title] for known phrases — in any language —
/// and returns the canonical English version. Returns null when the
/// title doesn't match any known event; caller should keep the original.
LocalizedAlert? reskinAlert(String title, String body) {
  final t = title.toLowerCase();

  if (t.contains('earthquake') || t.contains('deprem') || t.contains('tremor')) {
    return localizeAlert('earthquake', body);
  }
  if (t.contains('gas leak') || t.contains('gaz kaçağı') || t.contains('gaz kacagi')) {
    return localizeAlert('gas_leak', body);
  }
  if (t.contains('unauthorized') || t.contains('yetkisiz')) {
    return localizeAlert('rfid_unauthorized', body);
  }
  if (t.contains('door unlocked') || t.contains('kapı açıldı') || t.contains('kapi acildi')) {
    return localizeAlert('rfid_authorized', body);
  }
  if (t.contains('stove') || t.contains('ocak')) {
    return localizeAlert('stove_left_on', body);
  }
  if (t.contains('tv left on') || t.contains('tv idle') || t.contains('tv boşta')) {
    return localizeAlert('tv_idle_long', body);
  }
  if (t.contains('ac running') || t.contains('window open') || t.contains('pencere açık')) {
    return localizeAlert('ac_running_window_open', body);
  }
  if (t.contains('mood change') || t.contains('ruh hâli') || t.contains('ruh hali')) {
    return localizeAlert('emotion_change', body);
  }
  if (t.contains('device offline') || t.contains('disconnected') || t.contains('çevrimdışı')) {
    return localizeAlert('device_offline', body);
  }
  return null;
}
