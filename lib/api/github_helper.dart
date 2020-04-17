import 'package:ap_common/callback/general_callback.dart';
import 'package:ap_common/models/new_response.dart';
import 'package:big5/big5.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:html/parser.dart';
import 'package:nsysu_ap/models/tuition_and_fees.dart';

class GitHubHelper {
  static const BASE_PATH = 'https://raw.githubusercontent.com';

  static Dio dio;

  static CookieJar cookieJar;

  static GitHubHelper _instance;

  static bool isLogin = false;

  static GitHubHelper get instance {
    if (_instance == null) {
      _instance = GitHubHelper();
      cookieJar = CookieJar();
      dio = Dio();
      dio.interceptors.add(CookieManager(cookieJar));
      cookieJar.loadForRequest(Uri.parse(BASE_PATH));
    }
    return _instance;
  }

  Future<List<News>> getNews({GeneralCallback callback}) async {
    try {
      var response = await Dio().get(
        '$BASE_PATH/abc873693/NSYSU-AP/master/assets/news_data.json',
      );
      return NewsResponse.fromRawJson(response.data).data;
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