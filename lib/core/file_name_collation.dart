import 'package:lpinyin/lpinyin.dart';

/// 网盘文件名统一的显示排序键：拉丁字符按大小写不敏感比较，中文按拼音。
String lanzouNameSortKey(String name) =>
    PinyinHelper.getPinyinE(name, separator: '', defPinyin: '~').toLowerCase();
