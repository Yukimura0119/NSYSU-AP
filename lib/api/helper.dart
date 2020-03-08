import 'dart:convert';

import 'package:ap_common/models/course_data.dart';
import 'package:ap_common/models/new_response.dart';
import 'package:ap_common/models/time_code.dart';
import 'package:big5/big5.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:nsysu_ap/models/course_semester_data.dart';
import 'package:nsysu_ap/models/graduation_report_data.dart';
import 'package:nsysu_ap/models/options.dart';
import 'package:nsysu_ap/models/score_data.dart';
import 'package:nsysu_ap/models/score_semester_data.dart';
import 'package:nsysu_ap/models/tuition_and_fees.dart';
import 'package:nsysu_ap/models/user_info.dart';
import 'package:nsysu_ap/utils/utils.dart';

import '../utils/app_localizations.dart';
import '../utils/firebase_analytics_utils.dart';

const HOST = "nsysu-ap.rainvisitor.me";
const PORT = '8443';
const BASE_URL = 'https://$HOST:$PORT';

class Helper {
  static Helper _instance;
  static String courseCookie = '';
  static String scoreCookie = '';
  static String graduationCookie = '';
  static String tsfCookie = '';
  static String username = '';
  static String selcrsUrl = 'selcrs1.nsysu.edu.tw';
  static const String tfUrl = 'tfstu.nsysu.edu.tw';
  static int index = 0;
  static int error = 0;

  static Helper get instance {
    if (_instance == null) {
      _instance = Helper();
    }
    return _instance;
  }

  String get language {
    switch (AppLocalizations.locale.languageCode) {
      case 'zh':
        return 'cht';
        break;
      case 'en':
        return 'eng';
        break;
      default:
        return 'cht';
        break;
    }
  }

  static changeSelcrsUrl() {
    index++;
    if (index == 5) index = 0;
    selcrsUrl = 'selcrs${index == 0 ? '' : index}.nsysu.edu.tw';
    print(selcrsUrl);
  }

  String base64md5(String text) {
    var bytes = utf8.encode(text);
    var digest = md5.convert(bytes);
    return base64.encode(digest.bytes);
  }

  Future<int> selcrsLogin(String username, String password) async {
    var base64md5Password = base64md5(password);
    bool score = true, course = true;
    var scoreResponse = await http.post(
      'http://$selcrsUrl/scoreqry/sco_query_prs_sso2.asp',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'SID': username,
        'PASSWD': base64md5Password,
        'ACTION': '0',
        'INTYPE': '1',
      },
    ).timeout(Duration(seconds: 2));
    String text = big5.decode(scoreResponse.bodyBytes);
//    print('statusCode = ${scoreResponse.statusCode} text =  $text');
    if (text.contains("資料錯誤請重新輸入"))
      score = false;
    else if (scoreResponse.statusCode != 302 && scoreResponse.statusCode != 200)
      throw '';
    scoreCookie = scoreResponse.headers['set-cookie'];
    //print('scoreResponse statusCode =  ${scoreResponse.statusCode}');
    var courseResponse = await http.post(
      'http://$selcrsUrl/menu4/Studcheck_sso2.asp',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'stuid': username,
        'SPassword': base64md5Password,
      },
    ).timeout(Duration(seconds: 2));
    //print('courseResponse statusCode =  ${courseResponse.statusCode}');
    text = big5.decode(courseResponse.bodyBytes);
    //print('text =  $text');
    if (text.contains("學號碼密碼不符"))
      course = false;
    else if (courseResponse.statusCode != 302 &&
        courseResponse.statusCode != 200) throw '';
    courseCookie = courseResponse.headers['set-cookie'];
    print(DateTime.now());
    if (score && course)
      return 200;
    else
      return 403;
  }

  Future<int> graduationLogin(String username, String password) async {
    print(DateTime.now());
    var base64md5Password = base64md5(password);
    bool graduation = true;
    var response = await http.post(
      'http://$selcrsUrl/gadchk/gad_chk_login_prs_sso2.asp',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'SID': username,
        'PASSWD': base64md5Password,
        'PGKIND': 'GAD_CHK',
        'ACTION': '0',
      },
    ).timeout(Duration(seconds: 2));
    String text = big5.decode(response.bodyBytes);
//    print('Response =  $text');
//    print('response.statusCode = ${response.statusCode}');
    if (text.contains("資料錯誤請重新輸入"))
      graduation = false;
    else if (response.statusCode != 302 && response.statusCode != 200) throw '';
    graduationCookie = response.headers['set-cookie'];
    if (graduation) {
      Helper.username = username;
      return 200;
    } else
      return 403;
  }

  Future<UserInfo> getUserInfo() async {
    var url = 'http://$selcrsUrl/menu4/tools/changedat.asp';
    var response = await http.get(
      url,
      headers: {'Cookie': courseCookie},
    );
    String text = big5.decode(response.bodyBytes);
    //print('text =  ${text}');
    var document = parse(text, encoding: 'BIG-5');
    var tdDoc = document.getElementsByTagName('td');
    var userInfo = UserInfo();
    if (tdDoc.length > 0)
      userInfo = UserInfo(
        department: tdDoc[1].text,
        studentId: tdDoc[5].text,
        studentNameCht: tdDoc[7].text,
        educationSystem: tdDoc[9].text,
      );
    return userInfo;
  }

  Future<CourseSemesterData> getCourseSemesterData() async {
    var url = 'http://$selcrsUrl/menu4/query/stu_slt_up.asp';
    var response = await http.post(
      url,
      headers: {'Cookie': courseCookie},
      encoding: Encoding.getByName('BIG-5'),
    );
    String text = big5.decode(response.bodyBytes);
    //print('text =  ${text}');
    var document = parse(text, encoding: 'BIG-5');
    var options = document.getElementsByTagName('option');
    var courseSemesterData = CourseSemesterData(semesters: []);
    for (var i = 0; i < options.length; i++) {
      //print('$i => ${tdDoc[i].text}');
      courseSemesterData.semesters.add(
        Options(
          text: options[i].text,
          value: options[i].attributes['value'],
        ),
      );
    }
    return courseSemesterData;
  }

  Future<CourseData> getCourseData(
      String username, TimeCodeConfig timeCodeConfig, String semester) async {
    var url = 'http://$selcrsUrl/menu4/query/stu_slt_data.asp';
    var response = await http.post(
      url,
      headers: {'Cookie': courseCookie},
      body: {
        'stuact': 'B',
        'YRSM': semester,
        'Stuid': username,
        'B1': '%BDT%A9w%B0e%A5X',
      },
      encoding: Encoding.getByName('BIG-5'),
    );
    String text = big5.decode(response.bodyBytes);
    //print('text =  ${text}');
    var startTime = DateTime.now().millisecondsSinceEpoch;
    var document = parse(text, encoding: 'BIG-5');
    var trDoc = document.getElementsByTagName('tr');
    var courseData =
        CourseData(courseTables: (trDoc.length == 0) ? null : CourseTables());
    if (courseData.courseTables != null)
      courseData.courseTables.timeCode = timeCodeConfig.textList;
    //print(DateTime.now());
    for (var i = 0; i < trDoc.length; i++) {
      var tdDoc = trDoc[i].getElementsByTagName('td');
      if (i == 0) continue;
      final title = tdDoc[4].text;
      final instructors = tdDoc[8].text;
      final location = Location(
        building: '',
        room: tdDoc[9].text,
      );
      String time = '';
      for (var j = 10; j < tdDoc.length; j++) {
        if (tdDoc[j].text.length > 0) {
          List<String> sections = tdDoc[j].text.split('');
          if (sections.length > 0 && sections[0] != ' ') {
            String tmp = '';
            for (var section in sections) {
              int index = timeCodeConfig.indexOf(section);
              if (index == -1) continue;
              TimeCode timeCode = timeCodeConfig.timeCodes[index];
              tmp += '$section';
              var course = Course(
                title: title,
                instructors: [instructors],
                location: location,
                date: Date(
                  weekday: 'T',
                  section: section,
                  startTime: timeCode?.startTime ?? '',
                  endTime: timeCode?.endTime ?? '',
                ),
              );
              if (j == 10)
                courseData.courseTables.monday.add(course);
              else if (j == 11)
                courseData.courseTables.tuesday.add(course);
              else if (j == 12)
                courseData.courseTables.wednesday.add(course);
              else if (j == 13)
                courseData.courseTables.thursday.add(course);
              else if (j == 14)
                courseData.courseTables.friday.add(course);
              else if (j == 15)
                courseData.courseTables.saturday.add(course);
              else if (j == 16) courseData.courseTables.sunday.add(course);
            }
            if (tmp.isNotEmpty) {
              time += '${trDoc[0].getElementsByTagName('td')[j].text}$tmp';
            }
          }
        }
      }
      courseData.courses.add(
        CourseDetail(
          code: tdDoc[2].text,
          className: '${tdDoc[1].text} ${tdDoc[3].text}',
          title: title,
          units: tdDoc[5].text,
          required:
              tdDoc[7].text.length == 1 ? '${tdDoc[7].text}修' : tdDoc[7].text,
          location: location,
          instructors: [instructors],
          times: time,
        ),
      );
    }
    if (trDoc.length != 0) {
      if (courseData.courseTables.saturday.length == 0)
        courseData.courseTables.saturday = null;
      if (courseData.courseTables.sunday.length == 0)
        courseData.courseTables.sunday = null;
      var endTime = DateTime.now().millisecondsSinceEpoch;
      FA.logTimeEvent(FA.COURSE_HTML_PARSER, (endTime - startTime) / 1000.0);
    }
    //print(DateTime.now());
    return courseData;
  }

  Future<ScoreSemesterData> getScoreSemesterData() async {
    var url =
        'http://$selcrsUrl/scoreqry/sco_query.asp?ACTION=702&KIND=2&LANGS=$language';
    var response = await http.post(
      url,
      headers: {'Cookie': scoreCookie},
      encoding: Encoding.getByName('BIG-5'),
    );
    String text = big5.decode(response.bodyBytes);
    //print('text =  ${text}');
    var document = parse(text, encoding: 'BIG-5');
    var selectDoc = document.getElementsByTagName('select');
    var scoreSemesterData = ScoreSemesterData(
      semesters: [],
      years: [],
    );
    if (selectDoc.length >= 2) {
      var options = selectDoc[0].getElementsByTagName('option');
      for (var i = 0; i < options.length; i++) {
        scoreSemesterData.years.add(
          Options(
            text: options[i].text,
            value: options[i].attributes['value'],
          ),
        );
      }
      options = selectDoc[1].getElementsByTagName('option');
      for (var i = 0; i < options.length; i++) {
        scoreSemesterData.semesters.add(
          Options(
            text: options[i].text,
            value: options[i].attributes['value'],
          ),
        );
        if (options[i].attributes['selected'] != null)
          scoreSemesterData.selectSemesterIndex = i;
      }
    } else {
      print('document.text = ${document.text}');
    }
    return scoreSemesterData;
  }

  Future<ScoreData> getScoreData(String year, String semester) async {
    var url =
        'http://$selcrsUrl/scoreqry/sco_query.asp?ACTION=804&KIND=2&LANGS=$language';
    var response = await http.post(
      url,
      headers: {'Cookie': scoreCookie},
      body: {
        'SYEAR': year,
        'SEM': semester,
      },
      encoding: Encoding.getByName('BIG-5'),
    );
    String text = big5.decode(response.bodyBytes);
    var startTime = DateTime.now().millisecondsSinceEpoch;
    var document = parse(text, encoding: 'BIG-5');
    List<Score> list = [];
    Detail detail = Detail();
    var tableDoc = document.getElementsByTagName('tbody');
    if (tableDoc.length >= 2) {
//      for (var i = 0; i < tableDoc.length; i++) {
//        //print('i => ${tableDoc[i].text}');
//        var fontDoc = tableDoc[i].getElementsByTagName('tr');
//        for (var j = 0; j < fontDoc.length; j++) {
//          print("i $i j $j => ${fontDoc[j].text}");
//        }
//      }
      if (tableDoc.length == 3) {
        var fontDoc = tableDoc[1].getElementsByTagName('font');
        detail.conduct =
            '${fontDoc[0].text.split('：')[1]}/${fontDoc[1].text.split('：')[1]}';
        detail.average = fontDoc[2].text.split('：')[1];
        detail.classRank =
            '${fontDoc[4].text.split('：')[1]}/${fontDoc[5].text.split('：')[1]}';
        var percentage = double.parse(fontDoc[4].text.split('：')[1]) /
            double.parse(fontDoc[5].text.split('：')[1]);
        percentage = 1.0 - percentage;
        percentage *= 100;
        detail.classPercentage = '${percentage.toStringAsFixed(2)}';
      }
      var trDoc = tableDoc[0].getElementsByTagName('tr');
      for (var i = 0; i < trDoc.length; i++) {
        var fontDoc = trDoc[i].getElementsByTagName('font');
        if (fontDoc.length != 6) continue;
        if (i != 0)
          list.add(Score(
            number:
                '${fontDoc[2].text.substring(1, fontDoc[2].text.length - 1)}',
            title: //'${trDoc[i].getElementsByTagName('font')[2].text}'
                '${fontDoc[3].text}',
            middleScore: '${fontDoc[4].text}',
            finalScore: fontDoc[5].text,
          ));
      }
      var endTime = DateTime.now().millisecondsSinceEpoch;
      FA.logTimeEvent(FA.SCORE_HTML_PARSER, (endTime - startTime) / 1000.0);
    }
    /*var trDoc = document.getElementsByTagName('tr');
    for (var i = 0; i < trDoc.length; i++) {
      if (trDoc[i].getElementsByTagName('font').length != 6) continue;
      if (i != 0)
        list.add(Score(
          title: //'${trDoc[i].getElementsByTagName('font')[2].text}'
              '${trDoc[i].getElementsByTagName('font')[3].text}',
          middleScore: '${trDoc[i].getElementsByTagName('font')[4].text}',
          finalScore: trDoc[i].getElementsByTagName('font')[5].text,
        ));
      for (var j in trDoc[i].getElementsByTagName('font')) {
        //print('${j.text}');
      }
    }*/
    var scoreData = ScoreData(
      status: 200,
      messages: '',
      content: Content(
        scores: list,
        detail: detail,
      ),
    );
    if (list.length == 0) scoreData.status = 204;
    return scoreData;
  }

  Future<PreScore> getPreScoreData(String courseNumber) async {
    var url =
        'http://$selcrsUrl/scoreqry/sco_query.asp?ACTION=814&KIND=1&LANGS=$language';
    var response = await http.post(
      url,
      headers: {
        'Cookie': scoreCookie,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: {
        'CRSNO': courseNumber,
      },
      encoding: Encoding.getByName('BIG-5'),
    );
    String text = big5.decode(response.bodyBytes);
    var startTime = DateTime.now().millisecondsSinceEpoch;
    //print('text = $text}');
    var document = parse(text, encoding: 'BIG-5');
    PreScore detail;
    var tableDoc = document.getElementsByTagName('table');
    if (tableDoc.length >= 1) {
      for (var i = 0; i < tableDoc.length; i++) {
        var trDoc = tableDoc[i].getElementsByTagName('tr');
        if (trDoc.length >= 2) {
          var tdDoc = trDoc[1].getElementsByTagName('td');
          if (tdDoc.length >= 6) {
            detail = PreScore(
              item: tdDoc[2].text,
              percentage: tdDoc[3].text,
              originalGrades: tdDoc[4].text,
              grades: tdDoc[5].text,
              remark: tdDoc[6].text,
            );
          }
        }
      }
    }
    return detail;
  }

  Future<GraduationReportData> getGraduationReport() async {
    var url =
        'http://$selcrsUrl/gadchk/gad_chk_stu_list.asp?stno=$username&KIND=5&frm=1';
    var response = await http.get(
      url,
      headers: {'Cookie': graduationCookie},
    );
    var graduationReportData = GraduationReportData(
      missingRequiredCourse: [],
      generalEducationCourse: [],
      otherEducationsCourse: [],
    );
    String text = big5.decode(response.bodyBytes);
    var startTime = DateTime.now().millisecondsSinceEpoch;
    //print('text = $text');
    print(DateTime.now());
    var document = parse(text, encoding: 'BIG-5');
    var tableDoc = document.getElementsByTagName('tbody');
    if (tableDoc.length >= 2) {
      for (var i = 0; i < tableDoc.length; i++) {
        //print('i => ${tableDoc[i].text}');
        var trDoc = tableDoc[i].getElementsByTagName('tr');
        if (i == 4) {
          //缺修學系必修課程
          if (trDoc.length > 3) {
            for (var j = 2; j < trDoc.length; j++) {
              var tdDoc = trDoc[j].getElementsByTagName('td');
              if (tdDoc.length == 3)
                graduationReportData.missingRequiredCourse.add(
                  MissingRequiredCourse(
                    name: tdDoc[0].text,
                    credit: tdDoc[1].text,
                    description: tdDoc[2].text,
                  ),
                );
//              for (var k = 0; k < tdDoc.length; k++) {
//                print("i $i j $j k $k => ${tdDoc[k].text}");
//              }
            }
          }
          if (trDoc.length > 0) {
            graduationReportData.missingRequiredCoursesCredit =
                trDoc.last.text.replaceAll(RegExp(r'[※\n]'), '');
          }
        } else if (i == 5) {
          //通識課程
          for (var j = 2; j < trDoc.length; j++) {
            var tdDoc = trDoc[j].getElementsByTagName('td');
            //print('td lengh = ${tdDoc.length}');
            int base = 0;
            if (tdDoc.length == 7) {
              base = 1;
              graduationReportData.generalEducationCourse.add(
                GeneralEducationCourse(
                  type: tdDoc[0].text,
                  generalEducationItem: [],
                ),
              );
            }
            if (tdDoc.length > 5)
              graduationReportData
                  .generalEducationCourse.last.generalEducationItem
                  .add(
                GeneralEducationItem(
                  name: tdDoc[base + 0].text,
                  credit: tdDoc[base + 1].text,
                  check: tdDoc[base + 2].text,
                  actualCredits: tdDoc[base + 3].text,
                  totalCredits: tdDoc[base + 4].text,
                  practiceSituation: tdDoc[base + 5].text,
                ),
              );
          }
          if (graduationReportData.generalEducationCourse.length > 0) {
            graduationReportData.generalEducationCourseDescription =
                trDoc.last.text.replaceAll(RegExp(r'[※\n]'), '');
          }
        } else if (i == 6) {
          //其他
          if (trDoc.length > 3) {
            for (var j = 2; j < trDoc.length; j++) {
              var tdDoc = trDoc[j].getElementsByTagName('td');
              if (tdDoc.length == 3)
                graduationReportData.otherEducationsCourse.add(
                  OtherEducationsCourse(
                    name: tdDoc[0].text,
                    semester: tdDoc[1].text,
                    credit: tdDoc[2].text,
                  ),
                );
//              for (var k = 0; k < tdDoc.length; k++) {
//                print("i $i j $j k $k => ${tdDoc[k].text}");
//              }
            }
          }
          if (trDoc.length > 0) {
            graduationReportData.otherEducationsCourseCredit =
                trDoc.last.text.replaceAll(RegExp(r'[※\n]'), '');
          }
        }
      }
      var tdDoc = document.getElementsByTagName('td');
      for (var i = 0; i < tdDoc.length; i++) {
        if (tdDoc[i].text.contains('目前累計學分數'))
          graduationReportData.totalDescription =
              tdDoc[i].text.replaceAll(RegExp(r'[※\n]'), '');
      }
      print(DateTime.now());
    } else {
      return null;
    }
//    graduationReportData.generalEducationCourse.forEach((i) {
//      print('type = ${i.type}');
//    });
    var endTime = DateTime.now().millisecondsSinceEpoch;
    print((endTime - startTime) / 1000.0);
    return graduationReportData;
  }

  Future<String> getUsername(String name, String id) async {
    var url = 'http://$selcrsUrl/newstu/stu_new.asp?action=16';
    var encoded = Utils.uriEncodeBig5(name);
    var response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'CNAME': encoded,
        'T_CID': id,
        'B1': '%BDT%A9w%B0e%A5X',
      },
    );
    String text = big5.decode(response.bodyBytes);
    var document = parse(text, encoding: 'BIG-5');
    var elements = document.getElementsByTagName('b');
    if (elements.length > 0)
      return elements[0].text;
    else
      return '';
  }

  Future<int> tfLogin(String username, String password) async {
    var response = await http.post(
      'https://$tfUrl/tfstu/tfstu_login_chk.asp',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'ID': username,
        'passwd': password,
      },
    ).timeout(Duration(seconds: 2));
    String text = big5.decode(response.bodyBytes);
//    print('Response =  $text');
//    print('response.statusCode = ${response.statusCode}');
    tsfCookie = response.headers['set-cookie'];
    return response.statusCode;
  }

  Future<List<TuitionAndFees>> getTfData() async {
    var url = 'https://$tfUrl/tfstu/tfstudata.asp?act=11';
    var response = await http.get(
      url,
      headers: {'Cookie': tsfCookie},
    );
    String text = big5.decode(response.bodyBytes);
    //print('text =  ${text}');
    if (text.contains('沒有合乎查詢條件的資料')) {
      return null;
    }
    var document = parse(text, encoding: 'BIG-5');
    var tbody = document.getElementsByTagName('tbody');
    List<TuitionAndFees> list = [];
    var trElements = tbody[1].getElementsByTagName('tr');
    for (var i = 1; i < trElements.length; i++) {
      var tdDoc = trElements[i].getElementsByTagName('td');
      var aTag = tdDoc[4].getElementsByTagName('a');
      String serialNumber;
      if (aTag.length > 0) {
        serialNumber = aTag[0]
            .attributes['onclick']
            .split('javascript:window.location.href=\'')
            .last;
        serialNumber = serialNumber.substring(0, serialNumber.length - 1);
      }
      String paymentStatus = '', paymentStatusEn = '';
      for (var charCode in tdDoc[2].text.codeUnits) {
        if (charCode < 200) {
          if (charCode == 32)
            paymentStatusEn += '\n';
          else
            paymentStatusEn += String.fromCharCode(charCode);
        } else
          paymentStatus += String.fromCharCode(charCode);
      }
      final titleEN = tdDoc[0].getElementsByTagName('span')[0].text;
      list.add(
        TuitionAndFees(
          titleZH: tdDoc[0].text.replaceAll(titleEN, ''),
          titleEN: titleEN,
          amount: tdDoc[1].text,
          paymentStatusZH: paymentStatus,
          paymentStatusEN: paymentStatusEn,
          dateOfPayment: tdDoc[3].text,
          serialNumber: serialNumber ?? '',
        ),
      );
    }
    return list;
  }

  Future<List<int>> downloadFile(String serialNumber) async {
    var response = await http.get(
      'https://$tfUrl/tfstu/$serialNumber',
      headers: {'Cookie': tsfCookie},
    );
//    var bytes = response.bodyBytes;
//    await Printing.sharePdf(bytes: bytes, filename: filename);
//    await Printing.layoutPdf(
//      onLayout: (format) async => response.bodyBytes,
//    );
//    String dir = (await getApplicationDocumentsDirectory()).path;
//    File file = new File('$dir/$filename');
//    await file.writeAsBytes(bytes);
    return response.bodyBytes;
  }

  Future<List<News>> getNews() async {
    var response = await http.get(
      'https://raw.githubusercontent.com/abc873693/NSYSU-AP/master/assets/news_data.json',
      headers: {'Cookie': tsfCookie},
    );
    return NewsResponse.fromRawJson(response.body).data;
  }
}
