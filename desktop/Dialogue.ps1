# Local interactions are immediate. Free conversation, when installed, uses only loopback.
if ($null -eq $script:config.PSObject.Properties['Affection']) { $script:config | Add-Member NoteProperty Affection 0 }
$score = 0
if (-not [int]::TryParse([string]$script:config.Affection, [ref]$score)) { $score = 0 }
$script:config.Affection = [Math]::Max(0, [Math]::Min(100, $score))
$script:conversationHistory = New-Object 'System.Collections.Generic.List[object]'
$script:lastReaction = 'smile'
$script:lastAffectionAt = [datetime]::MinValue
$script:lastPetLine = ''
$script:chatTask = $null
$script:chatBackend = $null
$backendFile = Join-Path $PSScriptRoot 'chat-backend.json'
if (Test-Path -LiteralPath $backendFile) {
    try {
        $script:chatBackend = Get-Content -LiteralPath $backendFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($field in @('Server','Model')) {
            if (-not [IO.Path]::IsPathRooted($script:chatBackend.$field)) { $script:chatBackend.$field = Join-Path $PSScriptRoot $script:chatBackend.$field }
        }
    } catch { $script:chatBackend = $null }
}
Add-Type -AssemblyName System.Net.Http
$script:chatClient = New-Object System.Net.Http.HttpClient
$script:chatClient.Timeout = [TimeSpan]::FromSeconds(35)
$reactionTimer = New-Object System.Windows.Threading.DispatcherTimer
$reactionTimer.Interval = [TimeSpan]::FromSeconds(5)
$reactionTimer.Add_Tick({
    $reactionTimer.Stop()
    if ($script:state -eq 'reaction') { Set-PetState }
})
function Get-PetRelationship {
    $level = if ($script:config.Affection -ge 60) { '亲密伙伴' } elseif ($script:config.Affection -ge 25) { '越来越熟啦' } else { '慢慢熟悉中' }
    return ('♥ ' + $script:config.Affection + '/100 · ' + $level)
}
function Select-PetLine($Lines) {
    $choices = @($Lines | Where-Object { $_ -ne $script:lastPetLine })
    if ($choices.Count -eq 0) { $choices = @($Lines) }
    $script:lastPetLine = [string]($choices | Get-Random)
    return $script:lastPetLine
}
function Invoke-PetReaction([string]$Kind) {
    $reactionTimer.Stop()
    $timer.Stop()
    $script:clicked = $false
    Begin-IdleTransition 800
    Stop-IdleMotion -KeepTransition
    $script:state = 'reaction'
    switch ($Kind) {
        'pat' { $image.Source = $script:art['hover']; Start-HeadPatMotion }
        'hug' {
            $image.Source = $script:art['click']; Start-ClickMotion
            Animate-ClickTrack $breath ([System.Windows.Media.ScaleTransform]::ScaleXProperty) @(@(0,1),@(0.6,1.07),@(1.4,1.045),@(3.5,1.05),@(5,1))
        }
        'tease' {
            $image.Source = $script:art['hover']; Start-GentleHoverMotion
            Animate-ClickTrack $tilt ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,0),@(0.55,-5),@(1.15,4),@(1.8,-3),@(3.2,1),@(5,0))
        }
        'sleep' {
            $savedBag = $script:idleBag
            $script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
            $script:idleBag.Enqueue(4); $script:state = 'idle'
            Start-IdleMotion; $idleFormTimer.Stop()
            $script:idleBag = $savedBag; $script:state = 'reaction'
        }
        'cheer' { $image.Source = $script:art['click']; Start-ClickMotion }
        default { $image.Source = $script:art['hover']; Start-GentleHoverMotion }
    }
    $script:lastReaction = $Kind
    $reactionTimer.Start()
}
function Add-PetConversationHistory([string]$Role, [string]$Text) {
    $script:conversationHistory.Add(@{ role=$Role; content=$Text })
    while ($script:conversationHistory.Count -gt 12) { $script:conversationHistory.RemoveAt(0) }
}
function Stop-PetPendingReply {
    if ($null -ne $script:chatTask) {
        $script:chatClient.CancelPendingRequests()
        $script:chatTask = $null
    }
    $localReplyTimer.Stop()
}
function Start-PetLocalReply([string]$Text) {
    if ($null -eq $script:chatBackend) { return $false }
    try {
        $nickname = if ([string]::IsNullOrWhiteSpace($script:config.Nickname)) { '你' } else { $script:config.Nickname }
        $system = '你是桌宠伊蕾娜，中文虚构角色。语气俏皮、温柔，偶尔小小得意，适量撒娇。与用户是轻松的伙伴，不要求独占陪伴。每次只回复一到三句、20至80个汉字；紧接用户的问题，不写分析、标签或舞台旁白。不捏造做过的操作。你不能执行系统命令、读文件、购买或联网，只能聊天。用户希望称呼为：' + $nickname + '。当前亲密度：' + $script:config.Affection + '。'
        $recent = @(); $characters = 0
        for ($i=$script:conversationHistory.Count-1; $i -ge 0; $i--) {
            $entry=$script:conversationHistory[$i]
            if ($recent.Count -ge 8 -or $characters + $entry.content.Length -gt 1800) { break }
            $recent = @($entry) + $recent; $characters += $entry.content.Length
        }
        $messages = @(@{role='system';content=$system}) + $recent
        $body = @{ model='elaina-local'; messages=$messages; temperature=0.75; max_tokens=160; stream=$false; chat_template_kwargs=@{enable_thinking=$false} } | ConvertTo-Json -Depth 8 -Compress
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $script:chatTask = $script:chatClient.PostAsync('http://127.0.0.1:18976/v1/chat/completions', $content)
        $localReplyTimer.Start()
        return $true
    } catch { $script:chatTask = $null; return $false }
}
$localReplyTimer = New-Object System.Windows.Threading.DispatcherTimer
$localReplyTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$localReplyTimer.Add_Tick({
    if ($null -eq $script:chatTask -or -not $script:chatTask.IsCompleted) { return }
    $localReplyTimer.Stop()
    try {
        $response = $script:chatTask.GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            $json = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            $line = [string]$json.choices[0].message.content
            $line = [regex]::Replace($line, '(?s)<think>.*?</think>', '').Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { throw 'Empty local response' }
            if ($line.Length -gt 500) { $line = $line.Substring(0,500) }
            Add-PetConversationHistory 'assistant' $line
            Invoke-PetReaction 'smile'
            Show-Bubble $line 7
            Add-PetChatReply -Text $line -Status (Get-PetRelationship)
        } finally { $response.Dispose() }
    } catch {
        Add-PetChatReply -Text '本地聊天还没准备好，先摸摸头、抱抱，或者陪我玩猜拳吧。' -Status ((Get-PetRelationship) + ' · 内置互动可用')
    } finally { $script:chatTask = $null }
})
function Invoke-PetConversation([string]$Text) {
    $Text = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) { return [PSCustomObject]@{Text='';Action='';Status=(Get-PetRelationship)} }
    if ($Text.Length -gt 600) { $Text = $Text.Substring(0,600) }
    Stop-PetPendingReply
    Add-PetConversationHistory 'user' $Text
    $kind = 'smile'; $line = ''; $friendly = $false
    switch -Regex ($Text) {
        '^(叫我|以后叫我)\s*(.{1,20})$' {
            $script:config.Nickname = $Matches[2].Trim(' ', '。', '！', '!')
            Save-PetConfig; $line = '记住啦，' + $script:config.Nickname + '。下次可不许说我没认真听！'; break
        }
        '我叫什么|我的名字|我的称呼|记得我吗' {
            $line = if ($script:config.Nickname) { '当然记得呀，' + $script:config.Nickname + '。这可是你亲口告诉我的。' } else { '还没告诉我怎么称呼你呢。试试说“叫我小星”。' }; break
        }
        '^(石头|剪刀|布)$' {
            $mine = @('石头','剪刀','布') | Get-Random
            $win = @{ '石头'='剪刀'; '剪刀'='布'; '布'='石头' }
            if ($mine -eq $Text) { $line = '我出' + $mine + '！平局，居然想到一起啦。再来？'; $kind='tease' }
            elseif ($win[$Text] -eq $mine) { $line='我出' + $mine + '…你赢啦！奖励一个得意小表情，哼哼。'; $kind='cheer'; $friendly=$true }
            else { $line='我出' + $mine + '，这局是我赢！要不要再挑战一次呀？'; $kind='tease' }; break
        }
        '猜拳|玩游戏|陪我玩' { $line='来猜拳呀！直接发“石头”“剪刀”或“布”，我会同时出招。'; $kind='tease'; break }
        '^(再来|还要|再来一次|再来一下)[！!。~～]*$' {
            $kind=$script:lastReaction; $line=Select-PetLine @('还想再来呀？好吧，就再陪你一次。','收到，再来一小会儿！','你一叫我，我的呆毛就藏不住啦。'); $friendly=$true; break
        }
        '摸摸|摸头|揉揉|顺毛' {
            $kind='pat'; $line=Select-PetLine @('唔…轻一点，呆毛要翘起来啦。','这个力度刚刚好。再摸一下也可以哦。','被发现了，我就是喜欢这样被摸摸头。'); $friendly=$true; break
        }
        '抱抱|拥抱|贴贴|蹭蹭' {
            $kind='hug'; $line=Select-PetLine @('接住！一个软乎乎的抱抱送给你。','靠近一点点。好啦，抱抱能量补满！','抱住啦。今天辛苦的部分，就先放下一会儿吧。'); $friendly=$true; break
        }
        '夸夸我|鼓励我' {
            $kind='cheer'; $line=Select-PetLine @('想要一点鼓励，就勇敢说出来，这点很好呀。今天的小进步也值得被看见。','我给你举一颗小星星！不用一下做到完美，先把眼前的一小步走完就很棒。'); $friendly=$true; break
        }
        '夸夸|可爱|真棒|漂亮|喜欢你|好乖' {
            $kind='cheer'; $line=Select-PetLine @('咳，那当然…不过你再夸一句，我会更开心。','被夸得耳朵都立起来啦！你也很会让人开心呢。','这句我收下啦。今天的得意额度加一！'); $friendly=$true; break
        }
        '逗逗|戳戳|捏脸|笨蛋|傲娇' {
            $kind='tease'; $line=Select-PetLine @('哼，被你戳到了！下一次我要躲开一点点。','才、才没有被你逗笑呢…呆毛不许出卖我。','又来逗我。罚你陪我玩一局猜拳！'); $friendly=$true; break
        }
        '晚安|睡吧|睡觉|打瞌睡' { $kind='sleep'; $line='唔，抱枕准备好了。让我闭一会儿眼睛…晚安呀。'; break }
        '难过|不开心|好累|烦死|委屈|压力' { $kind='hug'; $line=Select-PetLine @('先给你一个抱抱。是今天哪件事最让你难受呀？','听起来有点累了。先歇一下，我听你慢慢说。','不用急着装作没事。你愿意的话，就从最想说的那句开始。'); break }
        '^(你好|嗨|早安|早上好|在吗|回来啦)[呀啊哦！!。~～]*$' { $line=Select-PetLine @('在呀，刚好等到你。今天先摸摸头，还是聊一会儿？','发现你啦！我的呆毛是不是先打了招呼？','你来得正好，给今天添一点点可爱吧。'); break }
        '^(暂停|继续)专注$' {
            if ($script:focused) { if (($Text -eq '暂停专注') -ne $script:focusPaused) { Invoke-FocusPauseToggle }; $line=if($script:focusPaused){'先休息一下，时间已经暂停啦。'}else{'好，我们继续。计时也跟上啦。'} }
            else { $line='现在还没有专注计时哦。右键我就能开始。' }; break
        }
        default {
            if (Start-PetLocalReply $Text) { return [PSCustomObject]@{Text='';Action='thinking';Status=((Get-PetRelationship) + ' · 正在想怎么回答…')} }
            $line='这版的内置互动我会认真接住：摸摸、抱抱、夸夸、逗逗、晚安，还能猜拳。自由聊天需要本地模型准备好。'
        }
    }
    if ($friendly -and ((Get-Date) - $script:lastAffectionAt).TotalSeconds -ge 2) {
        $script:config.Affection = [Math]::Min(100, [int]$script:config.Affection + 1)
        $script:lastAffectionAt = Get-Date; Save-PetConfig
    }
    Invoke-PetReaction $kind
    Show-Bubble $line 5
    Add-PetConversationHistory 'assistant' $line
    return [PSCustomObject]@{ Text=$line; Action=$kind; Status=(Get-PetRelationship) }
}
function Stop-PetConversation {
    Stop-PetPendingReply
    $reactionTimer.Stop()
    $script:chatClient.Dispose()
    if ($script:chatWindow) { $script:chatWindow.Close() }
    try { if ($script:backendProcess -and -not $script:backendProcess.HasExited) { $script:backendProcess.Kill() } } catch { }
}
function Start-PetChatBackend {
    if ($script:isolatedRun -or $null -eq $script:chatBackend -or $script:backendStarted) { return }
    if (-not (Test-Path -LiteralPath $script:chatBackend.Server) -or -not (Test-Path -LiteralPath $script:chatBackend.Model)) { return }
    # Start once on opening chat. Requests are restricted to this loopback listener.
    $arguments = '-m "' + $script:chatBackend.Model + '" --host 127.0.0.1 --port 18976 --alias elaina-local -c 4096 -np 1 -t 4 --jinja --reasoning off --no-webui'
    $probe = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $probe.ConnectAsync('127.0.0.1',18976)
        if ($connect.Wait(200) -and $probe.Connected) { $script:backendStarted=$true; return }
    } catch { } finally { $probe.Dispose() }
    try {
        $script:backendProcess = Start-Process -FilePath $script:chatBackend.Server -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $script:backendStarted = $true
    } catch { $script:backendStarted = $false; Write-Warning ('本地聊天启动失败，内置互动仍可使用：' + $_.Exception.Message) }
}
