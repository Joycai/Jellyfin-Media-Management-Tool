// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Jellyfin 媒体管理工具';

  @override
  String get manager => '管理';

  @override
  String get settings => '设置';

  @override
  String get mediaManager => '媒体管理器';

  @override
  String get pickDirectory => '选择目录';

  @override
  String get openDirectory => '打开目录';

  @override
  String get parentFolder => '上级目录';

  @override
  String get createNewFolder => '新建文件夹';

  @override
  String get refresh => '刷新';

  @override
  String get sortBy => '排序方式';

  @override
  String get sortByName => '按名称排序';

  @override
  String get sortByType => '按类型排序';

  @override
  String get sortByDate => '按日期排序';

  @override
  String get sortBySize => '按大小排序';

  @override
  String get ascending => '升序';

  @override
  String get descending => '降序';

  @override
  String get rename => '重命名';

  @override
  String get newName => '新名称';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get folderName => '文件夹名称';

  @override
  String get playVideo => '播放视频';

  @override
  String get openFile => '打开文件';

  @override
  String get renameFile => '重命名文件';

  @override
  String get operations => '操作';

  @override
  String get matchFolderName => '匹配文件夹名称';

  @override
  String get renameToFeaturette => '重命名为花絮 (Featurette)';

  @override
  String get renameToInterview => '重命名为访谈 (Interview)';

  @override
  String get renameToPart => '重命名为分段 (Part)...';

  @override
  String get renameToTVShow => '重命名为剧集 (SxxExx)...';

  @override
  String get jellyfinSubtitle => 'Jellyfin 标准字幕...';

  @override
  String get confirmRename => '确认重命名';

  @override
  String get renameFrom => '原名称:';

  @override
  String get renameTo => '新名称:';

  @override
  String get themeMode => '主题模式';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get system => '跟随系统';

  @override
  String get language => '语言';

  @override
  String get searchFromWeb => '从网页搜索';

  @override
  String get searchKeyword => '搜索关键词';

  @override
  String get searchSite => '搜索站点';

  @override
  String get search => '搜索';

  @override
  String get editSearchSites => '编辑搜索站点';

  @override
  String get siteName => '站点名称';

  @override
  String get searchUrl => '搜索 URL';

  @override
  String get addSite => '添加站点';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get openConfigFolder => '打开配置文件夹';

  @override
  String get areYouSure => '您确定吗？';

  @override
  String sizeLabel(Object size) {
    return '大小: $size';
  }

  @override
  String durationLabel(Object duration) {
    return '时长: $duration';
  }

  @override
  String resolutionLabel(Object resolution) {
    return '分辨率: $resolution';
  }

  @override
  String get noDirectorySelected => '未选择目录';

  @override
  String get pleaseSelectDirectory => '请选择一个目录';

  @override
  String get noPreviewAvailable => '无可用预览';

  @override
  String get directoriesCannotBePreviewed => '无法预览目录';

  @override
  String errorAccessingDirectory(Object error) {
    return '访问目录出错: $error';
  }

  @override
  String errorCreatingFolder(Object error) {
    return '创建文件夹出错: $error';
  }

  @override
  String errorRenaming(Object error) {
    return '重命名出错: $error';
  }

  @override
  String get noSearchSitesConfigured => '设置中未配置搜索站点';

  @override
  String get season => '季';

  @override
  String get episode => '集';

  @override
  String get selectPart => '选择分段';

  @override
  String get customPart => '自定义分段';

  @override
  String get customPartHint => '例如：5';

  @override
  String partLabel(Object count) {
    return '分段 $count';
  }

  @override
  String get tvShowDialogTitle => '剧集 (SxxExx)';

  @override
  String get apply => '应用';

  @override
  String get isDefault => '默认';

  @override
  String get languageLabel => '语言';

  @override
  String get subtitleLangZhHans => '简体中文';

  @override
  String get subtitleLangZhHant => '繁體中文';

  @override
  String get subtitleLangJa => '日本語';

  @override
  String get subtitleLangEn => 'English';

  @override
  String get video => '视频';

  @override
  String get appBrand => '媒体库整理';

  @override
  String get tabFiles => '文件';

  @override
  String get tabLibrary => '媒体库';

  @override
  String get tabTasks => '任务';

  @override
  String get comingSoon => '即将推出';

  @override
  String get searchHint => '搜索文件、电影、剧集…';

  @override
  String get favorites => '收藏';

  @override
  String get noFavorites => '暂无收藏';

  @override
  String get recent => '最近';

  @override
  String get noRecent => '暂无最近记录';

  @override
  String get locations => '位置';

  @override
  String get aiConnected => 'AI 服务已连接';

  @override
  String get aiConnectionError => 'AI 连接错误';

  @override
  String get aiTesting => '正在测试连接…';

  @override
  String get aiReady => 'AI 就绪';

  @override
  String get aiNotConfigured => 'AI 未配置';

  @override
  String itemsProcessed(Object count) {
    return '已处理 $count 项';
  }

  @override
  String get organizeWithAi => 'AI 整理全部';

  @override
  String organizeSelectedWithAi(Object count) {
    return 'AI 整理所选（$count）';
  }

  @override
  String get clearSelection => '清除选择';

  @override
  String get menuPreview => '预览';

  @override
  String get menuProperties => '属性';

  @override
  String get menuRevealInFileManager => '在系统文件管理器中显示';

  @override
  String get newNameLabel => '新名称';

  @override
  String deleteSelectedCount(Object count) {
    return '删除所选（$count）';
  }

  @override
  String deleteConfirmOne(Object name) {
    return '确定删除“$name”？此操作无法撤销。';
  }

  @override
  String deleteConfirmMany(Object count) {
    return '确定删除所选 $count 项？此操作无法撤销。';
  }

  @override
  String deletedCount(Object count) {
    return '已删除 $count 项';
  }

  @override
  String deleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String get revealFailed => '无法打开系统文件管理器';

  @override
  String get propModified => '修改时间';

  @override
  String get propPath => '路径';

  @override
  String get fontSection => '字体';

  @override
  String get fontSystem => '系统默认';

  @override
  String get fontStatusDownloaded => '已下载';

  @override
  String get fontStatusNotDownloaded => '需要下载';

  @override
  String get fontDownloadTitle => '下载字体';

  @override
  String fontDownloadConfirm(Object name) {
    return '首次使用 $name 需要下载一次官方字体包（保存到应用数据目录，仅需一次）。是否继续？';
  }

  @override
  String fontDownloading(Object name) {
    return '正在下载 $name…';
  }

  @override
  String fontDownloadFailed(Object error) {
    return '字体下载失败：$error';
  }

  @override
  String get downloadAction => '下载';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get noFolderOpen => '打开一个文件夹以开始';

  @override
  String get folderEmpty => '此文件夹为空';

  @override
  String get colName => '名称';

  @override
  String get colType => '类型';

  @override
  String get colSize => '大小';

  @override
  String get colAiSuggestion => 'AI 建议';

  @override
  String get colConfidence => '置信度';

  @override
  String get typeFolder => '文件夹';

  @override
  String get typeVideo => '视频';

  @override
  String get typeSubtitle => '字幕';

  @override
  String get typeImage => '图片';

  @override
  String get typeMetadata => '元数据';

  @override
  String get typeAudio => '音频';

  @override
  String get typeText => '文本';

  @override
  String get typeOther => '其他';

  @override
  String get needsReview => '需要人工确认';

  @override
  String get analyzing => '正在分析…';

  @override
  String get analysisComplete => '分析完成';

  @override
  String get notAnalyzed => '未分析';

  @override
  String selectedCount(Object count) {
    return '已选 $count 项';
  }

  @override
  String itemsCount(Object count) {
    return '共 $count 项';
  }

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get analyzingSelected => '正在分析所选文件';

  @override
  String get aiPanelIdle => '配置 AI 后整理文件夹';

  @override
  String get reasoning => '思考过程';

  @override
  String get targetStructure => '建议目标';

  @override
  String get previewOrganize => '预览整理';

  @override
  String get edit => '编辑';

  @override
  String get usage => '本次消耗';

  @override
  String tokensLabel(Object tokens) {
    return '$tokens tokens';
  }

  @override
  String get confirmApplyTitle => '应用整理？';

  @override
  String confirmApplyBody(Object count) {
    return '将把 $count 个文件移动并重命名为 Jellyfin 结构。';
  }

  @override
  String applyDone(Object count) {
    return '已整理 $count 个文件';
  }

  @override
  String applyPartial(Object failed, Object succeeded) {
    return '已整理 $succeeded 个，$failed 个失败';
  }

  @override
  String analyzeFailed(Object error) {
    return '失败：$error';
  }

  @override
  String get aiSettings => 'AI 服务';

  @override
  String get provider => '服务商';

  @override
  String get providerOpenAi => 'OpenAI 兼容';

  @override
  String get providerGoogle => 'Google GenAI';

  @override
  String get endpoint => '接入点';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get model => '模型';

  @override
  String get testConnection => '测试连接';

  @override
  String get connectionOk => '连接成功';

  @override
  String connectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get appearance => '外观';

  @override
  String get aiServicesTitle => 'AI 服务管理';

  @override
  String get aiServicesSubtitle => '配置用于整理媒体的语言模型';

  @override
  String get aiServiceDetailHint => '用于媒体整理和元数据匹配的 AI 端点';

  @override
  String get addService => '添加服务';

  @override
  String get addAnotherEndpoint => '添加另一个端点';

  @override
  String get newServiceName => '新服务';

  @override
  String get statusActive => '活跃';

  @override
  String get statusStandby => '备用';

  @override
  String get statusOffline => '离线';

  @override
  String get endpointProtocol => '端点协议';

  @override
  String get protocolOpenAi => 'OpenAI 兼容';

  @override
  String get protocolGoogle => 'Google GenAI';

  @override
  String get displayName => '显示名称';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get showKey => '显示';

  @override
  String get hideKey => '隐藏';

  @override
  String get defaultModel => '默认模型';

  @override
  String get temperature => '温度';

  @override
  String get tokensThisSession => '本次会话 token';

  @override
  String get requests => '请求数';

  @override
  String get avgLatency => '平均延迟';

  @override
  String get selectServiceHint => '选择左侧的服务进行配置';

  @override
  String get deleteServiceTitle => '删除服务';

  @override
  String deleteServiceConfirm(Object name) {
    return '删除「$name」？此操作无法撤销。';
  }

  @override
  String previewTitle(Object count) {
    return '确认整理 $count 项媒体到 Jellyfin 结构';
  }

  @override
  String previewSubtitle(Object folders, Object pct, Object size) {
    return '将移动 $folders 个文件夹、$size · AI 置信度 平均 $pct%';
  }

  @override
  String get viewTree => '树状对比';

  @override
  String get viewList => '查看清单';

  @override
  String get viewPoster => '海报视图';

  @override
  String get showOnly => '仅显示';

  @override
  String get filterChanges => '变更';

  @override
  String get filterAll => '全部';

  @override
  String filterConflicts(Object count) {
    return '冲突 ($count)';
  }

  @override
  String countMoves(Object count) {
    return '$count 移动';
  }

  @override
  String countRenames(Object count) {
    return '$count 重命名';
  }

  @override
  String countConflicts(Object count) {
    return '$count 冲突';
  }

  @override
  String get beforeLabel => '之前';

  @override
  String get afterLabel => '之后';

  @override
  String get aiOrganizeVertical => 'AI · JELLYFIN 整理';

  @override
  String get needsReviewSuffix => '待人工确认';

  @override
  String get recordUndoHistory => '记录撤销历史（保留 7 天）';

  @override
  String applyOrganizeCount(Object count) {
    return '应用整理（$count 项）';
  }

  @override
  String get editTargetTitle => '编辑目标路径';

  @override
  String get targetPathLabel => '目标路径（相对于整理的文件夹）';

  @override
  String get targetPathInvalid => '路径无效 — 必须位于整理的文件夹内';

  @override
  String get namingRules => '套用命名规则';

  @override
  String get editedBadge => '已修改';

  @override
  String get markResolved => '采纳此项';

  @override
  String organizing(Object count) {
    return '正在整理 · $count 项';
  }

  @override
  String get statusPaused => '已暂停';

  @override
  String get statusDone => '整理完成';

  @override
  String get statusStopped => '已停止';

  @override
  String etaRemaining(Object minutes, Object seconds) {
    return '预计剩余 $minutes 分 $seconds 秒';
  }

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get stop => '停止';

  @override
  String get doneClose => '完成';

  @override
  String get legendDone => '已完成';

  @override
  String get legendInProgress => '进行中';

  @override
  String get legendQueued => '排队';

  @override
  String get legendSkipped => '跳过';

  @override
  String logStarted(Object count) {
    return '开始整理 · $count 项';
  }

  @override
  String logMoved(Object dir, Object name) {
    return '移动 $name → $dir/';
  }

  @override
  String logSkipped(Object name) {
    return '$name · 待人工确认';
  }

  @override
  String logFailed(Object error, Object name) {
    return '失败 $name · $error';
  }

  @override
  String logFinished(Object done, Object skipped) {
    return '整理完成 · 完成 $done，跳过 $skipped';
  }

  @override
  String logStopped(Object done, Object skipped) {
    return '已停止 · 完成 $done，跳过 $skipped';
  }

  @override
  String get historyTitle => '操作历史';

  @override
  String historyRetention(Object days) {
    return '保留 $days 天';
  }

  @override
  String get historyEmpty => '暂无历史记录';

  @override
  String get historyUndoFootnote => '撤销会回退所有文件位置与命名，元数据缓存保留';

  @override
  String historyTitleAi(Object count) {
    return 'AI 整理 · $count 项';
  }

  @override
  String historyTitleManual(Object count) {
    return '手动重命名 · $count 项';
  }

  @override
  String get historyTitleMetadata => '元数据刷新';

  @override
  String historyTitleImport(Object count) {
    return '批量导入 · $count 项';
  }

  @override
  String subMoves(Object count) {
    return '移动 $count';
  }

  @override
  String subRenames(Object count) {
    return '重命名 $count';
  }

  @override
  String subWritten(Object count) {
    return '写入 $count';
  }

  @override
  String subReplaced(Object count) {
    return '替换 $count';
  }

  @override
  String get historyRowWritten => '新建';

  @override
  String get historyRowReplaced => '替换';

  @override
  String get undoAction => '撤销';

  @override
  String movesListTitle(Object count) {
    return '操作清单 · $count 项';
  }

  @override
  String undoDone(Object count) {
    return '已撤销 $count 个文件';
  }

  @override
  String undoPartial(Object failed, Object succeeded) {
    return '已撤销 $succeeded 个，$failed 个失败';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String timeToday(Object time) {
    return '今日 $time';
  }

  @override
  String get timeYesterday => '昨天';

  @override
  String timeDaysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String get secAppearance => '外观';

  @override
  String get secLanguage => '语言';

  @override
  String get secPaths => '路径与位置';

  @override
  String get breadcrumbPaths => '路径';

  @override
  String get secAiServices => 'AI 服务';

  @override
  String get secPrivacy => '隐私与缓存';

  @override
  String get secShortcuts => '快捷键';

  @override
  String get secAbout => '关于';

  @override
  String get versionUpToDate => '已是最新';

  @override
  String get theme => '主题';

  @override
  String get glassIntensity => '玻璃质感强度';

  @override
  String get glassNone => '无';

  @override
  String get glassSoft => '柔和';

  @override
  String get glassStrong => '强烈';

  @override
  String get accentColor => '强调色';

  @override
  String get behavior => '行为';

  @override
  String get behaviorAutoConnect => '启动时自动连接 AI 服务';

  @override
  String get behaviorAlwaysPreview => '应用整理前总是显示预览';

  @override
  String get behaviorLowConfSuggest => '置信度低于 60% 时仅建议、不自动应用';

  @override
  String get behaviorVideoThumbnails => '在文件列表中显示视频缩略图';

  @override
  String get privacyStorage => '本地存储';

  @override
  String get privacyConfigBody => '设置、AI 密钥和撤销清单都仅保存在本机。';

  @override
  String privacyClearHistory(Object count) {
    return '撤销全部 $count 条记录';
  }

  @override
  String privacyClearThumbnails(Object size) {
    return '清除缩略图缓存（$size）';
  }

  @override
  String get shortcutGroupNavigation => '导航';

  @override
  String get shortcutGroupSelection => '选择';

  @override
  String get shortcutGroupFiles => '文件';

  @override
  String get shortcutGroupApp => '应用';

  @override
  String get shortcutsHint => '在文本框中输入时快捷键不会触发（搜索快捷键除外）。';

  @override
  String get shortcutSearch => '聚焦搜索';

  @override
  String get shortcutParentFolder => '返回上级目录';

  @override
  String get shortcutOpenFolder => '打开文件夹';

  @override
  String get shortcutRefresh => '刷新文件列表';

  @override
  String get shortcutSectionFiles => '切换到「文件」';

  @override
  String get shortcutSectionLibrary => '切换到「媒体库」';

  @override
  String get shortcutSectionTasks => '切换到「任务」';

  @override
  String get shortcutSelectAll => '全选当前列表';

  @override
  String get shortcutEscape => '关闭对话框 · 清除搜索或选择';

  @override
  String get shortcutRename => '重命名当前文件';

  @override
  String get shortcutDelete => '删除选中项';

  @override
  String get shortcutOrganize => '使用 AI 整理';

  @override
  String get shortcutToggleFavorite => '收藏 / 取消收藏当前目录';

  @override
  String get shortcutHistory => '操作历史';

  @override
  String get shortcutSettings => '设置';

  @override
  String get aboutTagline => '面向 Jellyfin 的 AI 媒体整理工具。';

  @override
  String get aboutJellyfinNaming => 'Jellyfin 命名规范';

  @override
  String get langHeaderSubtitle => '切换会同步影响 AI 输出语言';

  @override
  String get langCurrent => '当前';

  @override
  String get langImportArb => '导入翻译文件 (.arb)';

  @override
  String get langImportSoon => '自定义翻译导入即将推出。';

  @override
  String get langPreviewTitle => '实时预览 · 主界面片段';

  @override
  String get langPreviewHint => '语言切换时，AI 提示词会同步翻译，整理结果中的 NFO 元数据语言也会随之调整。';

  @override
  String get langLearnMore => '了解更多';

  @override
  String get previewOrganizeSubtitle => '使用 AI 自动识别并移动到 Jellyfin 结构';

  @override
  String get previewConfidenceLabel => '置信度';

  @override
  String get previewConfidenceHigh => '高';

  @override
  String get previewTargetLabel => '建议目标';

  @override
  String get previewTargetValue => '电影/沙丘: 第二部 (2024)/';

  @override
  String onboardingStepCounter(Object current, Object total) {
    return '步骤 $current / $total';
  }

  @override
  String get onboardingWelcomeTitle => '欢迎使用 Jellyfin 整理器';

  @override
  String get onboardingWelcomeBody =>
      '让 AI 替你扫描凌乱的下载目录，自动重命名、归类，生成符合 Jellyfin 规范的媒体库结构。';

  @override
  String get onboardingSkip => '跳过引导';

  @override
  String get onboardingStart => '开始 →';

  @override
  String get onboardingStep1Eyebrow => '第一步';

  @override
  String get onboardingStep2Eyebrow => '第二步';

  @override
  String get onboardingRootTitle => '选择媒体库根目录';

  @override
  String get onboardingRootBody => '指定 Jellyfin 已经扫描的根路径，我们会把整理后的文件放在这里。';

  @override
  String get onboardingDropFolder => '拖拽文件夹到此处';

  @override
  String get onboardingOr => '或';

  @override
  String get onboardingPickFolder => '选择文件夹…';

  @override
  String get onboardingRootHint => '推荐: /Volumes/Media · ~/Movies';

  @override
  String get onboardingSkipForNow => '稍后再说';

  @override
  String get onboardingAiTitle => '连接你的 AI 服务';

  @override
  String get onboardingAiBody => '两种主流协议都支持。你也可以稍后在设置中添加。';

  @override
  String get onboardingProviderOpenAi => 'OpenAI 兼容端点';

  @override
  String get onboardingConfigureLater => '稍后配置';

  @override
  String get onboardingEnterWorkspace => '进入工作台 →';

  @override
  String get aiHintTitle => '提供标题（可选）';

  @override
  String get aiHintSubtitle => '告诉 AI 这是哪部电影或剧集，文件名残缺时也能准确归类。留空让 AI 自行推断。';

  @override
  String get aiHintLabel => '标题';

  @override
  String aiHintPlaceholder(Object folder) {
    return '例如：沙丘 · 流浪地球 · 鱿鱼游戏（默认：$folder）';
  }

  @override
  String get aiHintAnalyze => '开始分析';

  @override
  String get aiHintSkip => '跳过';

  @override
  String get aiHintKindLabel => '媒体类型';

  @override
  String get aiHintKindAuto => '自动判断';

  @override
  String get aiHintKindMovie => '电影';

  @override
  String get aiHintKindSeries => '剧集';

  @override
  String get aiHintLabelMovie => '电影名';

  @override
  String get aiHintLabelSeries => '剧名';

  @override
  String get tasksTitle => '任务';

  @override
  String get tasksEmpty => '暂无任务';

  @override
  String get tasksEmptyHint => 'AI 分析与整理任务会出现在这里';

  @override
  String get tasksClearFinished => '清理已完成';

  @override
  String tasksAnalyzeLabel(Object folder) {
    return 'AI 分析 · $folder';
  }

  @override
  String tasksApplyLabel(Object folder) {
    return '整理 · $folder';
  }

  @override
  String get tasksAnalyzeRunning => 'AI 正在分析…';

  @override
  String get tasksAnalyzeDone => '分析完成';

  @override
  String get tasksAnalyzeStarted => 'AI 分析已开始 · 进度在「任务」中查看';

  @override
  String get tasksApplyStarted => '整理任务已开始 · 在「任务」中查看进度';

  @override
  String get tasksRunning => '进行中';

  @override
  String get tasksDone => '完成';

  @override
  String get tasksFailed => '失败';

  @override
  String get tasksViewDetail => '查看详情';

  @override
  String get tasksDismiss => '移除';

  @override
  String tasksScrapeLabel(Object target) {
    return '刮削 · $target';
  }

  @override
  String tasksScrapeCommitLabel(Object target) {
    return '写入元数据 · $target';
  }

  @override
  String get menuScrapeMetadata => '刮削元数据';

  @override
  String get menuRescrapeFolder => '刷新文件夹内的元数据';

  @override
  String get batchScrapeTitle => '刷新元数据';

  @override
  String get batchScrapeScanning => '正在查找可刷新的条目…';

  @override
  String batchScrapeFound(Object count) {
    return '有 $count 个条目记录了当初的来源页。';
  }

  @override
  String get batchScrapeEmpty =>
      '这里没有可刷新的内容。只有本应用写入的 NFO 才会记录来源页，别处刮削的条目没有可回溯的地址。';

  @override
  String get batchScrapePolicy =>
      '每个条目都按安全默认值刷新：补空缺、保留已有值、列表合并。批量刷新不提供逐条确认 —— 需要逐条核对请对单个条目使用「刮削元数据」。';

  @override
  String get batchScrapeArtwork => '同时重新下载图片';

  @override
  String get batchScrapeArtworkHint => '默认关闭：图片在首次刮削时已经下载过了。';

  @override
  String batchScrapeStart(Object count) {
    return '刷新 $count 个条目';
  }

  @override
  String get batchScrapeStarted => '正在刷新元数据 —— 可在「任务」中查看进度';

  @override
  String batchScrapeDone(Object count) {
    return '已刷新 $count 个条目';
  }

  @override
  String batchScrapePartial(Object count, Object failed) {
    return '已刷新 $count 个条目 · $failed 个失败';
  }

  @override
  String get shortcutScrape => '为当前项刮削元数据';

  @override
  String get scrapeUrlTitle => '刮削元数据';

  @override
  String scrapeUrlSubtitle(Object target) {
    return '元数据将写入 $target 旁边';
  }

  @override
  String get scrapeUrlLabel => '作品页地址';

  @override
  String get scrapeUrlHint => 'https://example.com/product/12345';

  @override
  String get scrapeUrlInvalid => '请填写完整地址，需包含 http:// 或 https://';

  @override
  String scrapeDetectedCode(Object code) {
    return '识别到番号：$code';
  }

  @override
  String scrapeSearchOnSite(Object site) {
    return '在 $site 搜索';
  }

  @override
  String get scrapePasteHtml => '改为直接粘贴页面 HTML';

  @override
  String get scrapePasteHtmlHint => '在此粘贴页面源码';

  @override
  String get scrapePasteNeedsUrl => '地址仍然必填 —— 粘贴的 HTML 里的相对链接要靠它来解析。';

  @override
  String get scrapeCookieBuiltIn => '该站点已内置访问 Cookie。';

  @override
  String get scrapeCookieMissing =>
      '该站点未配置 Cookie。若抓取失败，可在「设置 → 刮削」里导入 cookies.txt。';

  @override
  String get scrapeStart => '开始刮削';

  @override
  String get scrapeStarted => '刮削已开始 —— 可在「任务」中查看进度';

  @override
  String scrapeFailed(Object error) {
    return '刮削失败：$error';
  }

  @override
  String get scrapeReady => '刮削完成 —— 请查看结果';

  @override
  String get scrapeReview => '查看';

  @override
  String get scrapeNoFolder => '请先打开一个文件夹';

  @override
  String get scrapeNoteSiteWideIgnored => '该站点每个页面都输出同一份 OpenGraph 数据，已忽略。';

  @override
  String get scrapeNoteNoRecipe => '没有匹配到该站点的配方 —— 只读取了页面自带的结构化数据。';

  @override
  String get scrapeNoteDegradedEncoding => '无法确定页面编码，部分文字可能是乱码。';

  @override
  String get scrapeNoteRecipeStale => '配方匹配上了但没抓到任何内容 —— 站点结构多半已经改版。';

  @override
  String get scrapeNoteRecipeLearned =>
      '该站点没有现成配方，已由 AI 生成一份。保存前请核对高亮的字段 —— 选择器选错时看起来完全正常，内容却可能被悄悄截断。';

  @override
  String get scrapeNoteRecipeLearningFailed =>
      'AI 没能弄清这个页面的结构。可以改用粘贴页面 HTML 再试一次。';

  @override
  String get scrapeNoteRedirectedAway =>
      '站点把请求重定向到了别处 —— 通常意味着需要先通过年龄确认或登录。下面显示的是落地页的内容，不是该作品的元数据。';

  @override
  String scrapeSaveRecipe(Object domain) {
    return '记住 $domain 的这份配方';
  }

  @override
  String scrapeRecipeSaved(Object domain) {
    return '已保存 $domain 的配方';
  }

  @override
  String get scrapePreviewTitle => '确认元数据';

  @override
  String scrapePreviewSubtitle(Object count, Object images) {
    return '$count 个字段 · $images 张图';
  }

  @override
  String get scrapeSource => '来源';

  @override
  String get scrapeRecipeName => '配方';

  @override
  String get scrapeRecipeNone => '无';

  @override
  String get scrapeColumnField => '字段';

  @override
  String get scrapeColumnExisting => '本地 NFO';

  @override
  String get scrapeColumnScraped => '抓取结果';

  @override
  String get scrapeColumnDecision => '操作';

  @override
  String get scrapeDecisionKeep => '保留';

  @override
  String get scrapeDecisionReplace => '替换';

  @override
  String get scrapeDecisionMerge => '合并';

  @override
  String get scrapePresetFillEmpty => '仅填补空白';

  @override
  String get scrapePresetReplaceAll => '全部替换';

  @override
  String get scrapePresetKeepAll => '全部保留';

  @override
  String get scrapeOriginStructured => '页面数据';

  @override
  String get scrapeOriginRecipe => '配方';

  @override
  String get scrapeOriginLlm => 'AI 推测';

  @override
  String get scrapeOriginExisting => '已有 NFO';

  @override
  String get scrapeOriginManual => '手动修改';

  @override
  String get scrapeOriginDerived => '推导';

  @override
  String get scrapeNoChanges => '没有需要改动的内容 —— 磁盘上的 NFO 已经包含这些信息。';

  @override
  String get scrapeWriteBackup => '记录撤销信息（并备份被替换的 NFO）';

  @override
  String get scrapeTargetFolder => '目标文件夹';

  @override
  String get scrapeNfoFileName => 'NFO 文件名';

  @override
  String get scrapeWrite => '写入';

  @override
  String scrapeEditValue(Object field) {
    return '编辑$field';
  }

  @override
  String get scrapeImages => '图片';

  @override
  String get scrapeImagePoster => '封面';

  @override
  String get scrapeImageFanart => '背景';

  @override
  String scrapeImageExtra(Object index) {
    return '样张 $index';
  }

  @override
  String scrapeImageCount(Object count, Object total) {
    return '已选 $count / $total';
  }

  @override
  String get scrapeImageNone => '该页面没有提供图片。';

  @override
  String get scrapeCommitStarted => '正在写入元数据 —— 可在「任务」中查看进度';

  @override
  String scrapeWriteSucceeded(Object count) {
    return '已写入 $count 个文件';
  }

  @override
  String scrapeWritePartial(Object count, Object failed) {
    return '已写入 $count 个文件 · $failed 个失败';
  }

  @override
  String scrapeWriteFailed(Object error) {
    return '没有写入任何内容：$error';
  }

  @override
  String get fieldTitle => '标题';

  @override
  String get fieldOriginalTitle => '原始标题';

  @override
  String get fieldSortTitle => '排序标题';

  @override
  String get fieldCode => '番号';

  @override
  String get fieldPlot => '简介';

  @override
  String get fieldOutline => '短介绍';

  @override
  String get fieldTagline => '标语';

  @override
  String get fieldPremiered => '发行日期';

  @override
  String get fieldRuntime => '时长';

  @override
  String get fieldStudio => '制作商';

  @override
  String get fieldSeries => '系列';

  @override
  String get fieldDirector => '导演';

  @override
  String get fieldRating => '评分';

  @override
  String get fieldGenres => '类型';

  @override
  String get fieldTags => '标签';

  @override
  String get fieldActors => '演员';

  @override
  String get fieldPoster => '封面';

  @override
  String get fieldFanart => '背景图';

  @override
  String get fieldExtraFanart => '样张';

  @override
  String get secScraping => '刮削';

  @override
  String get settingsScrapeCookies => 'Cookie';

  @override
  String get settingsScrapeCookieWarning =>
      '从浏览器导出的 cookies.txt 可能包含等同于登录态的会话凭证。Cookie 只保存在内存里，关闭应用即清空；浏览器里退出登录后也会失效，需要重新导入。';

  @override
  String get settingsScrapeImportCookies => '导入 cookies.txt';

  @override
  String get settingsScrapeClearCookies => '全部清除';

  @override
  String get settingsScrapeClearDomain => '清除';

  @override
  String get settingsScrapeCookieEmpty => '尚未导入 Cookie。';

  @override
  String settingsScrapeCookieCount(Object count) {
    return '$count 条 Cookie';
  }

  @override
  String settingsScrapeCookieImported(Object count) {
    return '已导入 $count 条 Cookie';
  }

  @override
  String get settingsScrapeCookieImportFailed => '该文件里没有可用的 Cookie';

  @override
  String get settingsScrapeRecipes => '站点配方';

  @override
  String get settingsScrapeRecipeBuiltin => '内置';

  @override
  String get settingsScrapeRecipeLearned => '学习';

  @override
  String get settingsScrapeRecipeUser => '手编';

  @override
  String get settingsScrapeRecipeRetired => '已退休';

  @override
  String get settingsScrapeRecipeDelete => '删除配方';

  @override
  String settingsScrapeRecipeHealth(Object count, Object failed) {
    return '成功 $count · 失败 $failed';
  }

  @override
  String get settingsScrapeRecipeAnyPath => '任意页面';

  @override
  String get scrapeNoteLlmExtracted =>
      '这些值由模型直接从页面读取，而非选择器匹配，没有任何环节核对过它们与原文是否一致。写入前请复核重要字段。';

  @override
  String get scrapeNoteLlmExtractionFailed => '模型未能从该页面读出可用的元数据。';

  @override
  String get scrapeAskLlm => '直接询问模型';

  @override
  String get scrapeAskLlmHint =>
      '由模型直接读取已抓取的页面并输出各字段。消耗一次请求，字段值以模型判断为准，而非页面原文。';

  @override
  String get scrapeCustomPrompt => '附加要求（可选）';

  @override
  String get scrapeCustomPromptHint => '给模型的额外要求，例如“简介保留日文”…';

  @override
  String get scrapeBackend => 'AI 后端';

  @override
  String get scrapeBackendNone => '尚未配置 AI 配置档';

  @override
  String get scrapeCookiesLabel => '该站点的 Cookie（可选）';

  @override
  String get scrapeCookiesHint => 'name=value; name2=value2 —— 仅在本次运行期间保存在内存中';

  @override
  String get scrapeNfoTarget => '对比 NFO';

  @override
  String get scrapeNfoBrowse => '浏览…';

  @override
  String scrapeNfoAutoDetected(Object name) {
    return '根据 $name 自动识别';
  }

  @override
  String get scrapePanelTitle => '刮削元数据';

  @override
  String get scrapeProcess => '开始处理';

  @override
  String get scrapeWorking => '处理中…';

  @override
  String get scrapeBackToSetup => '返回';

  @override
  String get scrapeRetry => '重试';

  @override
  String get scrapeAdvanced => '高级';

  @override
  String scrapeImageLoading(Object count) {
    return '加载中 $count…';
  }

  @override
  String get scrapeImageSelectAll => '全选';

  @override
  String get scrapeImageSelectNone => '全不选';

  @override
  String scrapeSaveImages(Object count) {
    return '保存 $count 张图片';
  }

  @override
  String get scrapeSaveImagesHint => '立即把勾选的图片写入媒体文件夹，不改动 NFO。';

  @override
  String scrapeSaveImagesDone(Object count, Object folder) {
    return '已保存 $count 张图片到 $folder';
  }

  @override
  String scrapeSaveImagesPartial(Object count, Object failed) {
    return '已保存 $count 张 · $failed 张失败';
  }

  @override
  String get scrapeImageRole => '标记为 Jellyfin 图片';

  @override
  String get scrapeRoleOriginal => '按原名保存';

  @override
  String get scrapeRolePoster => '海报 poster';

  @override
  String get scrapeRoleFanart => '背景图 fanart';

  @override
  String get scrapeRoleExtraFanart => '附加背景图';

  @override
  String get scrapeRoleLandscape => '横版图 landscape';

  @override
  String get scrapeRoleThumb => '缩略图 thumb';

  @override
  String get scrapeRoleBanner => '横幅 banner';

  @override
  String get scrapeRoleLogo => '标志 logo';

  @override
  String get scrapeRoleClearArt => '透明画 clearart';

  @override
  String get scrapeRoleDisc => '光盘图 disc';

  @override
  String get colResetWidths => '拖动调整列宽 · 双击恢复默认';

  @override
  String get scrapeSourceUrl => '产品页 URL';

  @override
  String get scrapeSourceSearch => '按文件名搜索站点';

  @override
  String get scrapeSearchKeyword => '搜索关键词';

  @override
  String get scrapeSearchNoSites => '尚未配置搜索站点 —— 可在「设置」中添加。';

  @override
  String scrapeNfoAutoMatched(Object name) {
    return '已自动匹配同目录的 $name';
  }

  @override
  String get scrapeStepFetch => '获取页面';

  @override
  String get scrapeStepExtract => '解析字段';

  @override
  String get scrapeStepCompare => '生成字段对比';

  @override
  String scrapeElapsed(Object time) {
    return '已用 $time';
  }

  @override
  String scrapeWillWrite(Object count) {
    return '$count 项将写入';
  }

  @override
  String get scrapeConflictLegend => '本地已有值且与抓取结果不同';

  @override
  String get scrapeImageRoleHint => '右键可标记为 Jellyfin 专用图片 · 其余按原文件名保存';

  @override
  String get scrapeImageUnmarked => '未标记';

  @override
  String get scrapeImageDeselect => '取消选择';

  @override
  String scrapeWriteCounts(Object fields, Object images) {
    return '写入 $fields 字段 + $images 图片';
  }

  @override
  String get previewDryRun => '预演 · 不会真实移动文件';

  @override
  String get previewFilterEmpty => '当前筛选没有条目';

  @override
  String get previewAdjustRules => '调整规则';

  @override
  String get ruleEditorTitle => '命名规则 · 电影';

  @override
  String get ruleEditorRecommended => 'Jellyfin 推荐';

  @override
  String get ruleEditorFolderTemplate => '文件夹路径模板';

  @override
  String get ruleEditorFileTemplate => '文件名模板';

  @override
  String get ruleEditorVariables => '可用变量';

  @override
  String get ruleEditorAiFill => 'AI 智能填充';

  @override
  String get ruleEditorAiFillHint => '当文件名无法解析时，自动调用 AI 推断标题、年份与语言。';

  @override
  String get ruleEditorPreview => '实时预览';

  @override
  String get ruleEditorInput => '输入';

  @override
  String get ruleEditorOutput => '输出';

  @override
  String get ruleEditorOutputAi => '输出 · AI 推断';

  @override
  String get ruleEditorReset => '重置';

  @override
  String get ruleEditorComingSoon => '规则编辑暂未生效 —— 当前展示的是内置的 Jellyfin 命名约定。';
}
