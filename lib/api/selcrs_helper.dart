import 'package:ap_common/callback/general_callback.dart';
import 'package:ap_common/models/course_data.dart';
import 'package:ap_common/models/general_response.dart';
import 'package:ap_common/models/score_data.dart';
import 'package:ap_common/models/time_code.dart';
import 'package:ap_common/models/user_info.dart';
import 'package:ap_common_firebase/utils/firebase_analytics_utils.dart';
import 'package:big5/big5.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:html/parser.dart';
import 'package:nsysu_ap/models/course_semester_data.dart';
import 'package:nsysu_ap/models/options.dart';
import 'package:nsysu_ap/models/pre_score.dart';
import 'package:nsysu_ap/models/score_semester_data.dart';
import 'package:nsysu_ap/utils/utils.dart';
import 'package:sprintf/sprintf.dart';
import 'package:cookie_jar/cookie_jar.dart';

import '../utils/app_localizations.dart';

class SelcrsHelper {
  static const selcrsUrlFormat = 'http://selcrs%i.nsysu.edu.tw';

  static SelcrsHelper _instance;

  static Dio dio;
  static CookieJar cookieJar;

  String username = '';
  String password = '';

  static String get selcrsUrl => sprintf(selcrsUrlFormat, [index]);

  static int index = 1;
  static int error = 0;

  static SelcrsHelper get instance {
    if (_instance == null) {
      _instance = SelcrsHelper();
      dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          sendTimeout: 10000,
          receiveTimeout: 10000,
        ),
      );
      initCookiesJar();
    }
    return _instance;
  }

  String get language {
    switch (AppLocalizations.locale.languageCode) {
      case 'en':
        return 'eng';
      case 'zh':
      default:
        return 'cht';
    }
  }

  Options get _courseOption => Options(
        responseType: ResponseType.bytes,
        contentType: Headers.formUrlEncodedContentType,
      );

  Options get _scoreOption => Options(
        responseType: ResponseType.bytes,
        contentType: Headers.formUrlEncodedContentType,
      );

  static changeSelcrsUrl() {
    index++;
    if (index == 5) index = 1;
    print(selcrsUrl);
    cookieJar.loadForRequest(Uri.parse('${SelcrsHelper.selcrsUrl}'));
  }

  static initCookiesJar() {
    cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    cookieJar.loadForRequest(Uri.parse('${SelcrsHelper.selcrsUrl}'));
  }

  void logout() {
    username = '';
    password = '';
    index = 1;
    error = 0;
    initCookiesJar();
  }

  /*
  * 選課系統&成績系統登入
  * error status code
  * 400: 帳號密碼錯誤
  * 401: 需要填寫表單
  * 499: 未知錯誤
  * */
  Future<void> login({
    @required String username,
    @required String password,
    @required GeneralCallback<GeneralResponse> callback,
  }) async {
    var base64md5Password = Utils.base64md5(password);
    dio.options.contentType = Headers.formUrlEncodedContentType;
    try {
      var scoreResponse = await dio.post(
        '$selcrsUrl/scoreqry/sco_query_prs_sso2.asp',
        data: {
          'SID': username,
          'PASSWD': base64md5Password,
          'ACTION': '0',
          'INTYPE': '1',
        },
      );
      String text = big5.decode(scoreResponse.data);
      if (text.contains("資料錯誤請重新輸入")) {
        callback?.onError(
          GeneralResponse(statusCode: 400, message: 'score error'),
        );
      } else {
        callback?.onError(
          GeneralResponse(statusCode: 499, message: 'unknown error'),
        );
      }
    } on DioError catch (e) {
      if (e.type == DioErrorType.RESPONSE && e.response.statusCode == 302) {
      } else {
        error++;
        if (error > 5)
          callback?.onFailure(e);
        else {
          changeSelcrsUrl();
          return login(
            username: username,
            password: password,
            callback: callback,
          );
        }
      }
    }
    try {
      var courseResponse = await dio.post(
        '$selcrsUrl/menu4/Studcheck_sso2.asp',
        data: {
          'stuid': username,
          'SPassword': base64md5Password,
        },
      );
      String text = big5.decode(courseResponse.data);
      print('text =  $text');
      if (text.contains("學號碼密碼不符")) {
        callback?.onError(
          GeneralResponse(statusCode: 400, message: 'course error'),
        );
      } else if (text.contains('請先填寫')) {
        callback?.onError(
          GeneralResponse(statusCode: 401, message: 'need to fill out form'),
        );
      } else {
        callback?.onError(
          GeneralResponse(statusCode: 499, message: 'unknown error'),
        );
      }
      print(DateTime.now());
    } on DioError catch (e) {
      if (e.type == DioErrorType.RESPONSE && e.response.statusCode == 302) {
        this.username = username;
        this.password = password;
        callback?.onSuccess(GeneralResponse.success());
      } else {
        error++;
        if (error > 5)
          callback?.onFailure(e);
        else {
          changeSelcrsUrl();
          return login(
            username: username,
            password: password,
            callback: callback,
          );
        }
      }
    }
  }

  /*
  * 取得使用者資訊
  * error status code
  * 400: 帳號密碼錯誤
  * */
  Future<UserInfo> getUserInfo({
    GeneralCallback<UserInfo> callback,
  }) async {
    try {
      var response = await dio.get(
        '$selcrsUrl/menu4/tools/changedat.asp',
      );
      String text = big5.decode(response.data);
      return callback?.onSuccess(parserUserInfo(text));
    } on DioError catch (e) {
      callback?.onFailure(e);
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  UserInfo parserUserInfo(String text) {
    var document = parse(text, encoding: 'BIG-5');
    var tdDoc = document.getElementsByTagName('td');
    var userInfo = UserInfo();
    if (tdDoc.length > 0)
      userInfo = UserInfo(
        department: tdDoc[1].text,
        className: tdDoc[3].text.replaceAll(' ', ''),
        id: tdDoc[5].text,
        name: tdDoc[7].text,
        email: tdDoc[9].text,
      );
    return userInfo;
  }

  Future<CourseSemesterData> getCourseSemesterData({
    GeneralCallback<CourseSemesterData> callback,
  }) async {
    var url = '$selcrsUrl/menu4/query/stu_slt_up.asp';
    try {
      var response = await dio.post(url);
      String text = big5.decode(response.data);
      //print('text =  ${text}');
      var document = parse(text, encoding: 'BIG-5');
      var options = document.getElementsByTagName('option');
      var courseSemesterData = CourseSemesterData(semesters: []);
      for (var i = 0; i < options.length; i++) {
        //print('$i => ${tdDoc[i].text}');
        courseSemesterData.semesters.add(
          SemesterOptions(
            text: options[i].text,
            value: options[i].attributes['value'],
          ),
        );
      }
      return callback?.onSuccess(courseSemesterData);
    } on DioError catch (e) {
      if (callback != null)
        callback.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  Future<CourseData> getCourseData({
    @required String username,
    @required TimeCodeConfig timeCodeConfig,
    @required String semester,
    GeneralCallback<CourseData> callback,
  }) async {
    var url = '$selcrsUrl/menu4/query/stu_slt_data.asp';
    try {
      var response = await dio.post(
        url,
        data: {
          'stuact': 'B',
          'YRSM': semester,
          'Stuid': username,
          'B1': '%BDT%A9w%B0e%A5X',
        },
        options: _courseOption,
      );
      String text = big5.decode(response.data);
      //    print('text =  ${text}');
      var startTime = DateTime.now().millisecondsSinceEpoch;
      var document = parse(text, encoding: 'BIG-5');
      var trDoc = document.getElementsByTagName('tr');
      var courseData =
          CourseData(courseTables: (trDoc.length == 0) ? null : CourseTables());
      if (courseData.courseTables != null)
        courseData.courseTables.timeCode = timeCodeConfig.textList;
      //print(DateTime.now());
      for (var i = 1; i < trDoc.length; i++) {
        var tdDoc = trDoc[i].getElementsByTagName('td');
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
                  detailIndex: i - 1,
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
        FirebaseAnalyticsUtils.instance
            .logTimeEvent('course_html_parser', (endTime - startTime) / 1000.0);
      }
      //print(DateTime.now());
      return callback?.onSuccess(courseData);
    } on DioError catch (e) {
      if (callback != null)
        callback.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  Future<ScoreSemesterData> getScoreSemesterData({
    GeneralCallback<ScoreSemesterData> callback,
  }) async {
    var url =
        '$selcrsUrl/scoreqry/sco_query.asp?ACTION=702&KIND=2&LANGS=$language';
    try {
      var response = await dio.post(
        url,
        options: _scoreOption,
      );
      String text = big5.decode(response.data);
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
            SemesterOptions(
              text: options[i].text,
              value: options[i].attributes['value'],
            ),
          );
        }
        options = selectDoc[1].getElementsByTagName('option');
        for (var i = 0; i < options.length; i++) {
          scoreSemesterData.semesters.add(
            SemesterOptions(
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
      return callback.onSuccess(scoreSemesterData);
    } on DioError catch (e) {
      if (callback != null)
        callback.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  Future<ScoreData> getScoreData({
    @required String year,
    @required String semester,
    bool searchPreScore = false,
    GeneralCallback<ScoreData> callback,
  }) async {
    var url =
        '$selcrsUrl/scoreqry/sco_query.asp?ACTION=804&KIND=2&LANGS=$language';
    try {
      var response = await dio.post(
        url,
        options: _scoreOption,
        data: {
          'SYEAR': year,
          'SEM': semester,
        },
      );
      String text = big5.decode(response.data);
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
          detail.creditTaken = double.parse(fontDoc[0].text.split('：')[1]);
          detail.creditEarned = double.parse(fontDoc[1].text.split('：')[1]);
          detail.average = double.parse(fontDoc[2].text.split('：')[1]);
          detail.classRank =
              '${fontDoc[4].text.split('：')[1]}/${fontDoc[5].text.split('：')[1]}';
          var percentage = double.parse(fontDoc[4].text.split('：')[1]) /
              double.parse(fontDoc[5].text.split('：')[1]);
          percentage = 1.0 - percentage;
          percentage *= 100;
          detail.classPercentage = double.parse(percentage.toStringAsFixed(2));
        }
        var trDoc = tableDoc[0].getElementsByTagName('tr');
        for (var i = 0; i < trDoc.length; i++) {
          var fontDoc = trDoc[i].getElementsByTagName('font');
          if (fontDoc.length != 6) continue;
          if (i != 0) {
            final score = Score(
              courseNumber:
                  '${fontDoc[2].text.substring(1, fontDoc[2].text.length - 1)}',
              title: //'${trDoc[i].getElementsByTagName('font')[2].text}'
                  '${fontDoc[3].text}',
              middleScore: '${fontDoc[4].text}',
              finalScore: fontDoc[5].text,
            );
            if (searchPreScore &&
                (score.finalScore == null ||
                    (score.finalScore ?? '') == '--')) {
              final preScore = await getPreScoreData(score.courseNumber);
              if (preScore != null) {
                score.finalScore = preScore.grades;
                score.isPreScore = true;
              }
            }
            list.add(score);
          }
        }
        var endTime = DateTime.now().millisecondsSinceEpoch;
        FirebaseAnalyticsUtils.instance
            .logTimeEvent('score_html_parser', (endTime - startTime) / 1000.0);
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
        scores: list,
        detail: detail,
      );
      return callback?.onSuccess(scoreData);
    } on DioError catch (e) {
      if (callback != null)
        callback.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  Future<PreScore> getPreScoreData(String courseNumber) async {
    var url =
        '$selcrsUrl/scoreqry/sco_query.asp?ACTION=814&KIND=1&LANGS=$language';
    var response = await dio.post(
      url,
      options: _scoreOption,
      data: {
        'CRSNO': courseNumber,
      },
    );
    String text = big5.decode(response.data);
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

  Future<String> getUsername({
    @required String name,
    @required String id,
    GeneralCallback<String> callback,
  }) async {
    var url = '$selcrsUrl/newstu/stu_new.asp?action=16';
    try {
      var encoded = Utils.uriEncodeBig5(name);
      var response = await dio.post(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          contentType: Headers.formUrlEncodedContentType,
        ),
        data: {
          'CNAME': encoded,
          'T_CID': id,
          'B1': '%BDT%A9w%B0e%A5X',
        },
      );
      String text = big5.decode(response.data);
      var document = parse(text, encoding: 'BIG-5');
      var elements = document.getElementsByTagName('b');
      return callback.onSuccess(elements.length > 0 ? elements[0].text : '');
    } on DioError catch (e) {
      if (callback != null)
        callback.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }

  Future<UserInfo> changeMail({
    @required String mail,
    @required GeneralCallback<UserInfo> callback,
  }) async {
    try {
      var response = await dio.post(
        '$selcrsUrl/menu4/tools/changedat.asp',
        options: _courseOption,
        data: {
          'T1': mail,
        },
      );
      String text = big5.decode(response.data);
      return callback?.onSuccess(parserUserInfo(text));
    } on DioError catch (e) {
      if (callback != null)
        callback?.onFailure(e);
      else
        throw e;
    } on Exception catch (e) {
      callback?.onError(GeneralResponse.unknownError());
      throw e;
    }
    return null;
  }
}
