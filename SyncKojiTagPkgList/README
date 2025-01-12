# SyncKojiTagPkgList

这个脚本用于把一个koji上的tag里的包列表同步到另外一个koji的tag

`python main.py [options] <source_kojihub> <source_tag> <target_kojihub> <target_tag>`

其中kojihub可以是Kojihub URL，也可以是本地的一个koji profile名

## 参数
--dry-run: 仅输出，不实际执行

--override-owner <owner>: 指定新的包拥有者

## 举例
假设本地有一个名为openkoji的koji配置文件且具有管理员权限

`python main.py --override-owner kojiadmin https://koji.fedoraproject.org/kojihub/ f42 openkoji f42`

上述命令将官方koji中的f42 tag里的包列表同步到本地openkoji的f42 tag中
