// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get manager => '管理';

  @override
  String get settings => '设置';

  @override
  String get parentFolder => '上级目录';

  @override
  String get refresh => '刷新';

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
  String get search => '搜索';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get openConfigFolder => '打开配置文件夹';

  @override
  String sizeLabel(Object size) {
    return '大小: $size';
  }

  @override
  String get noPreviewAvailable => '无可用预览';

  @override
  String errorRenaming(Object error) {
    return '重命名出错: $error';
  }

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
  String get appBrand => 'Jellyfin Media Management Tool';

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
  String applyDone(Object count) {
    return '已整理 $count 个文件';
  }

  @override
  String applyPartial(Object failed, Object succeeded) {
    return '已整理 $succeeded 个，$failed 个失败';
  }

  @override
  String get provider => '服务商';

  @override
  String get endpoint => '接入点';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get model => '模型';

  @override
  String get testConnection => '测试连接';

  @override
  String connectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get appearance => '外观';

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
  String get useThisService => '使用此服务';

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
  String get apiKeyOptionalHint => '本地服务（LM Studio、Ollama 等）可留空';

  @override
  String get contextWindow => '上下文窗口（tokens）';

  @override
  String get contextWindowHint => '留空 = 不限制';

  @override
  String get maxOutputTokens => '最大输出 tokens';

  @override
  String get maxOutputTokensHint => '留空 = 服务端默认';

  @override
  String get contextWindowNote =>
      '本应用无法修改服务端的上下文大小。请在加载模型的地方（LM Studio、Ollama、llama.cpp）设置，并在此填写相同数值：之后较大的文件夹会分批整理，刮削的网页也会裁剪到可容纳的长度。';

  @override
  String get connectionIncomplete => '请先填写 Base URL 和模型（Google 还需要 API 密钥）';

  @override
  String connectionOkReply(Object ms, Object reply) {
    return '连接成功，耗时 $ms ms。模型回复：$reply';
  }

  @override
  String get connectionEmptyReply => '（空回复）';

  @override
  String get connectionTruncated => '回复触达输出上限，整理前请调高最大输出 tokens。';

  @override
  String detectedContextWindow(Object source, Object tokens) {
    return '$source 报告上下文窗口为 $tokens tokens';
  }

  @override
  String detectedModelMaximum(Object source, Object tokens) {
    return '$source 报告模型最多支持 $tokens tokens，实际加载的可能更小';
  }

  @override
  String detectedMaxOutput(Object tokens) {
    return '最大输出 $tokens';
  }

  @override
  String get limitsNotDetected => '服务端未报告上下文大小，请在加载模型的地方查看。';

  @override
  String get useDetectedValue => '使用';

  @override
  String get samplingTitle => '采样参数';

  @override
  String samplingPresetMatched(Object name) {
    return '$name 推荐值';
  }

  @override
  String get samplingPresetSource => '出处';

  @override
  String get samplingNoPreset => '未识别模型家族，使用服务端默认';

  @override
  String get samplingReset => '恢复推荐值';

  @override
  String get samplingDefault => '默认';

  @override
  String get samplingTopP => 'Top P';

  @override
  String get samplingTopK => 'Top K';

  @override
  String get samplingMinP => 'Min P';

  @override
  String get samplingPresencePenalty => '存在惩罚';

  @override
  String get samplingRepeatPenalty => '重复惩罚';

  @override
  String get samplingNote => '留空即使用推荐值。';

  @override
  String get thinkingMode => '思考模式';

  @override
  String get thinkingModeHint => '默认关闭：思考会让本地小模型明显变慢，并容易绕圈子。';

  @override
  String get thinkingAlwaysOn => '此模型只能以思考模式运行。';

  @override
  String get thinkingEffortOnly => '此模型无法关闭思考；关闭时以低强度运行。';

  @override
  String get thinkingVerifiedOff => '上次测试：思考已关闭。';

  @override
  String get thinkingStillOn =>
      '上次测试：模型仍在思考。请在服务端的模型设置中关闭思考（LM Studio 中为 Enable Thinking）。';

  @override
  String get toolsSupported => '工具调用：支持。此模型可用于整理文件夹与刮削元数据。';

  @override
  String get toolsUnsupported => '工具调用：不支持。此模型无法用于整理文件夹或刮削元数据。';

  @override
  String get presetNeedsSystemPrompt =>
      '该模型的模型卡要求使用专用的 system prompt，缺少时效果可能变差。';

  @override
  String get ollamaIgnoresSampling =>
      'Ollama 的 OpenAI 兼容接口会忽略 Top K、Min P 和重复惩罚，请在 Modelfile 中设置。';

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
  String logUndoLost(Object error) {
    return '无法撤销 · $error';
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
  String get glassNone => '关闭';

  @override
  String get glassSoft => '柔和';

  @override
  String get glassStrong => '强烈';

  @override
  String get glassOffHint => '毛玻璃已关闭：面板改用不透明底色。这是界面最省的一档。';

  @override
  String get glassOnHint => '拖到 0 可彻底关闭毛玻璃。强度本身几乎不影响性能；模糊怎么算在下面「行为」里选。';

  @override
  String get accentColor => '强调色';

  @override
  String get behavior => '行为';

  @override
  String get behaviorBakedGlass => '预渲染毛玻璃';

  @override
  String get behaviorBakedGlassDesc =>
      '把窗口背景的模糊烘一次重复使用，而不是每帧重算。GPU 开销低得多，面板观感一致。';

  @override
  String get behaviorBakedGlassUnavailable => '毛玻璃已关闭，没有模糊可预渲染。';

  @override
  String get behaviorVideoThumbnails => '在文件列表中显示视频缩略图';

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
  String get aboutGpuHint =>
      'Windows 分配给本应用的 GPU。可在「设置 → 系统 → 屏幕 → 显示卡」中更改，改后需重启应用。';

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
  String get onboardingWelcomeTitle => '欢迎使用 Jellyfin Media Management Tool';

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
  String get scrapeUrlInvalid => '请填写完整地址，需包含 http:// 或 https://';

  @override
  String scrapeDetectedCode(Object code) {
    return '识别到番号：$code';
  }

  @override
  String get scrapePasteHtml => '改为直接粘贴页面 HTML';

  @override
  String get scrapePasteHtmlHint => '在此粘贴页面源码';

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
  String get scrapeOriginMerged => '合并';

  @override
  String get scrapeNoChanges => '没有需要改动的内容 —— 磁盘上的 NFO 已经包含这些信息。';

  @override
  String get scrapeWriteBackup => '记录撤销信息（并备份被替换的 NFO）';

  @override
  String get scrapeTargetFolder => '目标文件夹';

  @override
  String get scrapeNfoFileName => 'NFO 文件名';

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
  String get scrapeNoteLlmExtractionTruncated =>
      '模型在完成之前触到了输出上限，部分字段可能缺失。请在 AI 服务设置里调高最大输出。';

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
  String get scrapeKindMovie => '电影';

  @override
  String get scrapeKindTvShow => '剧集';

  @override
  String get scrapePanelTitle => '刮削元数据';

  @override
  String get scrapeProcess => '开始处理';

  @override
  String get scrapeWorking => '处理中…';

  @override
  String get scrapeBackToSetup => '返回';

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
  String get scrapeRolePoster => '封面 folder';

  @override
  String get scrapeRoleFanart => '背景图 backdrop';

  @override
  String get scrapeRoleExtraFanart => '附加背景图';

  @override
  String get scrapeRoleThumb => '缩略图 landscape';

  @override
  String get scrapeRoleMenu => '菜单图 menu';

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

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '向下还原';

  @override
  String get windowClose => '关闭';

  @override
  String get togglePanel => '显示或隐藏右侧面板';

  @override
  String get searchHintShort => '搜索…';

  @override
  String statusTotalSize(String size) {
    return '总计 $size';
  }

  @override
  String get planReady => '方案已就绪';

  @override
  String get dropFoldersTitle => '把文件夹拖到这里';

  @override
  String get dropFoldersHint => '支持单个或多个文件夹 · 视频、字幕、海报与元数据会一并扫描';

  @override
  String get orSeparator => '或';

  @override
  String get connectNas => '连接 NAS';

  @override
  String get historyAllRecords => '全部记录';

  @override
  String get historyIrreversible => '不可撤销';

  @override
  String get historyToday => '今天';

  @override
  String get back => '返回';

  @override
  String get pathsLibraryRoots => '媒体库根目录';

  @override
  String get pathsRootMovies => '电影';

  @override
  String get pathsRootShows => '剧集';

  @override
  String get pathsRootExample => '/Volumes/Media/Movies';

  @override
  String get pathsMounted => '已连接';

  @override
  String get pathsUnmounted => '未挂载';

  @override
  String get pathsChange => '更改';

  @override
  String get pathsAddRoot => '添加根目录';

  @override
  String get pathsRescan => '重新扫描';

  @override
  String get pathsRootsPlaceholder => '本应用一次只整理一个文件夹；多根目录、挂载状态与重新扫描尚未实现。';

  @override
  String get pathsDefaults => '默认位置';

  @override
  String get pathsOrganizeOutput => '整理输出位置';

  @override
  String get pathsOrganizeOutputValue => '跟随源目录';

  @override
  String get pathsChoose => '选择…';

  @override
  String get pathsTempDir => '临时与下载目录';

  @override
  String get pathsTempDirValue => '系统临时目录';

  @override
  String get pathsNfoOutput => 'NFO 与图片写入位置';

  @override
  String get pathsNfoOutputValue => '与媒体文件同目录';

  @override
  String get pathsDefaultsPlaceholder => '整理后的文件始终落在源目录内；单独的输出目录与临时目录尚未实现。';

  @override
  String get pathsFavorites => '收藏的路径';

  @override
  String get pathsFavoritesHint => '拖拽排序尚未实现；此处就是侧边栏的「收藏」分组。';

  @override
  String get pathsRecent => '最近访问';

  @override
  String get pathsClearRecent => '清除记录';

  @override
  String pathsRecentHint(Object count) {
    return '保留最近 $count 条；行尾的星号可加入收藏。';
  }

  @override
  String get pathsAddFavorite => '加入收藏';

  @override
  String get privacyLocations => '配置与数据位置';

  @override
  String get privacyConfigFolder => '配置文件夹';

  @override
  String get privacyBrowse => '浏览';

  @override
  String get privacyCopyPath => '复制';

  @override
  String get privacyCopied => '已复制路径';

  @override
  String get privacyDataFiles => '数据文件';

  @override
  String get privacyDataFilesValue =>
      'config.json · ai_profiles.json · ai_learned.json · sites.json · scrapers.json';

  @override
  String get privacyPrefsBackup => '偏好设置备份';

  @override
  String get privacyPrefsBackupHint => '导出或恢复 config.json 与 AI 服务配置';

  @override
  String get privacyImport => '导入';

  @override
  String get privacyExport => '导出';

  @override
  String get privacyCaches => '缓存';

  @override
  String get privacyClear => '清理';

  @override
  String get privacyClearAll => '全部清理';

  @override
  String get privacyTotal => '合计';

  @override
  String get privacyCacheThumbnails => '缩略图缓存';

  @override
  String get privacyCacheThumbnailsHint => '文件列表的视频首帧';

  @override
  String get privacyCacheUndo => '撤销备份';

  @override
  String privacyCacheUndoHint(Object count, Object days) {
    return '被覆盖文件的真副本，保留 $days 天 · 共 $count 条记录';
  }

  @override
  String get privacyCacheAgent => '整理记忆';

  @override
  String get privacyCacheAgentHint => '已决定的分组与已应用的更正';

  @override
  String get privacyCacheNote =>
      '清理只删除本地缓存，不影响已写入媒体库的 NFO 与图片，下次运行会重新生成。撤销备份没有「清理」：删掉它等于把还没过期的撤销记录变成空头支票。';

  @override
  String get privacySection => '隐私';

  @override
  String get privacyTelemetry => '发送匿名使用统计';

  @override
  String get privacyTelemetryHint => '不含文件名与路径';

  @override
  String get privacyCrashReports => '崩溃报告';

  @override
  String get privacyCrashReportsHint => '仅堆栈与设备型号';

  @override
  String get privacyLogAiBodies => '记录 AI 请求与回复正文';

  @override
  String privacyLogAiBodiesHint(int days) {
    return '每个实际发出的请求写入 logs 目录，按天一个文件，保留 $days 天。不写入密钥；图片与长文本只记长度。';
  }

  @override
  String get privacyClearTempOnExit => '退出时清空临时目录';

  @override
  String get privacyNoTelemetry => '本应用不采集任何遥测数据。AI 请求日志只写在本机，其余几项暂无可关。';

  @override
  String get privacyCacheApiLog => 'AI 请求日志';

  @override
  String get privacyCacheApiLogHint => '开启「记录 AI 请求与回复正文」后写入';

  @override
  String get privacyDanger => '危险操作';

  @override
  String get privacyReset => '重置所有数据';

  @override
  String get privacyResetBody =>
      '清空 AI 服务、规则、历史与全部缓存，应用回到首次启动状态。磁盘上的媒体文件不会被删除，已写入的 NFO 与图片保留。';

  @override
  String get privacyResetAction => '重置…';

  @override
  String get privacyResetPlaceholder =>
      '尚未实现。在那之前请手动删除配置文件夹 —— 一个不可撤销的重置不应该半成品上线。';

  @override
  String get shortcutsSearchHint => '搜索命令或按键…';

  @override
  String get shortcutsRestoreDefaults => '恢复默认';

  @override
  String get shortcutsRebindHint => '改绑尚未实现 —— 这里列出的就是实际生效的绑定。';

  @override
  String get shortcutsNoMatch => '没有匹配的命令';

  @override
  String get shortcutsPlatformNote =>
      'Windows 与 Linux 上 ⌘ → Ctrl、⌥ → Alt、⌫ → Delete。';

  @override
  String get aboutChangelog => '更新日志';

  @override
  String get aboutCheckUpdates => '检查更新';

  @override
  String get aboutBuildInfo => '构建信息';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutBuildNumber => '构建号';

  @override
  String get aboutCommit => '提交';

  @override
  String get aboutCommitTime => '提交时间';

  @override
  String get aboutBranch => '分支';

  @override
  String get aboutRuntime => '运行时';

  @override
  String get aboutBuildInfoPlaceholder => '提交号与分支需要在打包时注入，当前构建还没有做这一步。';

  @override
  String get aboutSystem => '系统';

  @override
  String get aboutOpenSource => '开源与版权';

  @override
  String get aboutLicense => '许可证';

  @override
  String get aboutRepository => '仓库';

  @override
  String get aboutIssues => '问题反馈';

  @override
  String get aboutCopyright => '版权';

  @override
  String get aboutCopyrightValue => '© 2026 贡献者';

  @override
  String get aboutThirdParty => '第三方许可';

  @override
  String get aboutGraphics => '图形设备';

  @override
  String get aboutGpuRunning => '当前运行';

  @override
  String get aboutGpuShared => '共享内存';

  @override
  String aboutGpuCount(Object count) {
    return '检测到 $count 个 GPU';
  }

  @override
  String get aboutGpuInfoOnly => '仅信息展示';

  @override
  String get aboutGpuIdle => '空闲';

  @override
  String get accentPickerTitle => '强调色';

  @override
  String get accentRestoreDefault => '恢复默认蓝';

  @override
  String get accentRecents => '最近使用';

  @override
  String get accentRecentsEmpty => '暂无';

  @override
  String get accentEyedropper => '从屏幕取色';

  @override
  String accentContrastOk(Object dark, Object light) {
    return '与深 / 浅两套底色对比 $dark:1 · $light:1';
  }

  @override
  String accentContrastWeak(Object dark, Object light) {
    return '对比 $dark:1 · $light:1 —— 低于 3:1，仅建议用于底色';
  }

  @override
  String get modelParameters => '模型参数';

  @override
  String get modelParametersExpand => '展开';

  @override
  String get modelParametersCollapse => '收起';

  @override
  String get modelParametersSaved => '模型参数已保存';

  @override
  String get contextWindowScaleHint => 'tokens · 8k – 1M · 步进 1k';

  @override
  String get contextWindowFootnote =>
      '刻度等距分段，段内连续，把手可停在任意 1k；输入与滑块双向联动。留空 = 不限制。';

  @override
  String contextWindowOverDetected(Object limit) {
    return '超过服务端上报的 $limit，仍可保存。';
  }

  @override
  String get maxOutputStep => '步进 256';

  @override
  String get maxOutputFootnote => '上限为上下文窗口的一半，超出即夹紧。';

  @override
  String get pathsRootExampleShows => '/Volumes/Media/Shows';

  @override
  String historyTitleTransfer(Object count) {
    return '复制 / 移动 · $count 项';
  }

  @override
  String tasksCopyLabel(Object target) {
    return '复制 · $target';
  }

  @override
  String tasksMoveLabel(Object target) {
    return '移动 · $target';
  }

  @override
  String get shortcutCopy => '复制选中项';

  @override
  String get shortcutCut => '剪切选中项';

  @override
  String get shortcutPaste => '粘贴到当前文件夹';

  @override
  String get menuCopy => '复制';

  @override
  String get menuCut => '剪切';

  @override
  String get menuPaste => '粘贴';

  @override
  String get menuPasteIntoFolder => '粘贴到此文件夹';

  @override
  String get menuMoveTo => '移动到…';

  @override
  String clipboardCopiedCount(Object count) {
    return '已复制 $count 项';
  }

  @override
  String clipboardCutCount(Object count) {
    return '已剪切 $count 项';
  }

  @override
  String get clipboardPasteHere => '粘贴到这里';

  @override
  String get clipboardClear => '清除';

  @override
  String transferConflictTitle(Object count, Object folder) {
    return '$folder 中已有 $count 个同名项';
  }

  @override
  String get transferConflictBody => '不会覆盖任何文件。可以跳过已存在的项，或两者都保留 —— 新副本会加上编号。';

  @override
  String get transferSkipExisting => '跳过已存在的';

  @override
  String get transferKeepBoth => '两者都保留';

  @override
  String get transferNothingToDo => '这里没有可粘贴的内容';

  @override
  String transferRefusedMissing(Object count) {
    return '$count 项已不存在';
  }

  @override
  String get transferRefusedIntoItself => '文件夹不能粘贴到自身内部';

  @override
  String transferRefusedSameFolder(Object count) {
    return '$count 项已在此文件夹中';
  }

  @override
  String transferCopiedCount(Object count) {
    return '已复制 $count 项';
  }

  @override
  String transferMovedCount(Object count) {
    return '已移动 $count 项';
  }

  @override
  String transferFailedCount(Object count) {
    return '$count 项失败';
  }

  @override
  String transferStopped(Object count) {
    return '已在 $count 项后停止';
  }

  @override
  String get transferNoUndo => '无法撤销';

  @override
  String get transferDestinationMissing => '目标文件夹不可用';

  @override
  String get moveToTitle => '移动到文件夹';

  @override
  String transferRefusedLink(Object count) {
    return '$count 项是符号链接或包含符号链接';
  }

  @override
  String transferRefusedUnreadable(Object count) {
    return '$count 项无法读取';
  }
}
