import 'package:intl/intl.dart';

class DateFormats {
  const DateFormats._();

  static final erpDateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final erpDate = DateFormat('yyyy-MM-dd');
  static final dayMonth = DateFormat('EEE, dd MMM');
  static final shortTime = DateFormat('hh:mm a');
  static final historyDate = DateFormat('dd MMM yyyy');

  static String forErp(DateTime dateTime) {
    return erpDateTime.format(dateTime.toLocal());
  }
}
