import 'package:intl/intl.dart';

class DateFormats {
  const DateFormats._();

  static const istOffset = Duration(hours: 5, minutes: 30);

  static final erpDateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final erpDate = DateFormat('yyyy-MM-dd');
  static final dayMonth = DateFormat('EEE, dd MMM');
  static final shortTime = DateFormat('hh:mm a');
  static final historyDate = DateFormat('dd MMM yyyy');
  static final istClock = DateFormat('hh:mm:ss a');

  static String forErp(DateTime dateTime) {
    return forErpIst(dateTime);
  }

  static DateTime istNow([DateTime? source]) {
    return (source ?? DateTime.now()).toUtc().add(istOffset);
  }

  static DateTime istDayStart([DateTime? source]) {
    final ist = istNow(source);
    return DateTime(ist.year, ist.month, ist.day);
  }

  static DateTime istDayEnd([DateTime? source]) {
    final start = istDayStart(source);
    return DateTime(start.year, start.month, start.day, 23, 59, 59);
  }

  static String todayIstDate([DateTime? source]) {
    return erpDate.format(istNow(source));
  }

  static String forErpIst(DateTime dateTime) {
    return erpDateTime.format(istNow(dateTime));
  }

  static String forErpIstWallClock(DateTime istWallClock) {
    return erpDateTime.format(istWallClock);
  }
}
