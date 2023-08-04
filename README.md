## scan-dep.sh
用来扫描哪些包依赖了某个包
### 参数：
--tag (-t) <tag>
    (必选项) 执行koji中哪个tag的包会被处理

--search (-s) <regex>
    筛选出匹配该正则表达式的包来后续查询

--requires (-r) <regex>
    (必选项) 当某个包的RPM的Requires匹配该正则表达式时就视为匹配

--branch (-b) <fedora_branch>
    在rebuild时，指定使用哪个branch

--rebuild
    检测到有包匹配时，自动rebuild

--nobuild
    检测到有包匹配时，不会自动rebuild

--output (-o) <file>
    把匹配的包输出到指定文件

--profile (-p) <profile_name>
    指定koji命令中-p参数的值

--url (-u) <koji_hub_url>
    Koji hub的URL

--concurrency (-c) <num_threads>
    并发数量

--timeout <seconds>
    设置curl操作的超时时间，单位为秒

### 举例：
- `bash scan-dep.sh -t f38-build-side-42-init-devel -r "php\(api\) = 20210902-64" -s "^php-" -p openkoji -c 4 -b f38 --output php-exe-rebuild-list.txt` \
  解释：脚本先使用koji命令（koji命令自动包含koji -p openkoji，即使用openkoji的profile）筛选`f38-build-side-42-init-devel` tag中的所有包，再筛选出包名匹配正则表达式`^php-`的包（即php-开头），而后开启4线程查找这其中是否有包的Requires中存在依赖名匹配正则表达式`php\(api\) = 20210902-64`的包，如果有，则克隆Fedora Source上的Git仓库，并切换到f38分支后向koji提交SRPM，且该包名追加写入php-exe-rebuild-list.txt的文件

- `bash scan-dep.sh -t f38-build-side-42-init-devel -r "libminiz\.so\.0\.2" -s "^perl-" -p openkoji -c 1 --timeout 10 --nobuild` \
  解释：除了上述例子里已经解释的参数外，--timeout则设置了curl超时时间为10秒，--nobuild则指定程序在查到符合条件的包时不会自动提交rebuild，且没有--output参数时，符合条件的包不会被写入本地文件
