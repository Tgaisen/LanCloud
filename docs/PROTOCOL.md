# 蓝奏云非官方接口笔记（自用客户端参考）

来源（MIT/Apache 开源实现，仅作协议参考）：
- https://github.com/zaxtyson/LanZouCloud-API （Python, MIT）
- https://github.com/chenhb23/lanzouyun-disk （TypeScript, MIT）
- https://github.com/nekobyran/lanzouplus （Java, MIT）

## 基础地址
- 网盘 API：https://pc.woozooo.com/doupload.php
- 上传：https://pc.woozooo.com/fileup.php
- 面板：https://pc.woozooo.com/account.php / mydisk.php
- 分享页主机：https://pan.lanzouo.com （备用 lanzouw.com / lanzoui.com / lanzoux.com）

## 登录
- Cookie 登录：设置 `ylogin`（uid）+ `phpdisk_info`，GET account.php 验证（页面含"网盘用户登录"即失败）。
- 账号密码登录已弃用，容易触发滑块验证，不建议在 App 内做。

## 列表
- 文件列表：POST doupload.php `{task:5, folder_id:<id|-1>, pg:<页码>}` → JSON
  `{info, text:[{id,name_all,time,size,downs,onof,is_des}]}`；`info==0` 表示没有更多页。
- 文件夹列表：POST `doupload.php?uid=<ylogin>` `{task:47, folder_id:<id>}` → `{text:[{fol_id,name,onof,folder_des}], info:[{folderid,name}]}`（info 为路径）。

## 上传
- POST https://pc.woozooo.com/fileup.php，multipart：
  `task=1, vie=2, ve=2, id=WU_FILE_0, folder_id_bb_n=<folder_id>, name=<文件名>` + 文件字段。
- 响应 `{zt:1, text:[{id,...}]}`；`zt==1` 成功。免费账号单文件 ≤100MB。
- 文件名有后缀白名单限制；免费账号重命名文件（task 46）需要会员。

## 下载直链（登录态，按文件 id）
1. 取分享信息：POST doupload.php `{task:22, file_id:<id>}` → `{info:{is_newd, f_id, pwd, onof, name}}`。
2. 分享 URL = `is_newd + '/' + f_id`（有提取码时用 `pwd`）。
3. GET 分享页；若响应是 JS 挑战页，用 `acw_sc__v2` 算法（unsbox + hex_xor，见 LanZouCloud-API utils.py）算出 cookie 后重试。
4. 无密码：提取 iframe 的 `src`，GET 之，取 `'sign':...`（可能藏在变量里）。
   有密码：首屏直接有 `sign=xxx&`，另带 `p=<提取码>`。
5. POST `{host}/ajaxm.php` `{action:'downprocess', sign, ves:1}`（有密码时 `{action:'downprocess', sign, p}`）→ `{zt:1, dom, url}`。
6. GET `dom + '/file/' + url`（不跟随重定向），`Location` 即真实直链；若页面提示"网络异常"，走验证流程。

## 管理操作（doupload.php）
- 新建文件夹：task 2 `{parent_id, folder_name, folder_description}`
- 重命名文件夹：task 4 `{folder_id, folder_name, folder_description}`
- 重命名文件：task 46 `{file_id, file_name, type:2}`（会员）
- 删除文件：task 6 `{file_id}`；删除文件夹：task 3 `{folder_id}`
- 移动文件：task 20 `{file_id, folder_id}`；全部文件夹树：task 19 `{file_id:-1}`
- 设置描述：task 11 `{file_id, desc}`；提取码：文件 task 23 / 文件夹 task 16
- 通用成功标志：响应 `zt == 1`

## 注意
- 建议设置 Referer 与浏览器 UA；Accept-Language: zh-CN,zh;q=0.9 对直链解析必要。
- 高频访问可能触发滑块/风控；自用小规模使用风险低。
