package com.codevoke.android.data

data class CodevokeProject(
    val name: String,
    val path: String,
    val selected: Boolean = false,
)

data class CodevokeSession(
    val title: String,
    val subtitle: String,
    val selected: Boolean = false,
)

data class CodevokeModel(
    val title: String,
    val subtitle: String,
    val selected: Boolean = false,
)

data class CodevokeFileEntry(
    val name: String,
    val type: String,
)

data class CodevokeDevice(
    val name: String,
    val platform: String,
    val online: Boolean,
)

data class CodevokeMessage(
    val text: String,
    val fromUser: Boolean,
    val secondary: String? = null,
)

object SampleData {
    val projects = listOf(
        CodevokeProject("ClaudeMac", "/Users/oreo/Desktop/ClaudeMac", selected = true),
        CodevokeProject("通讯软件", "/Users/oreo/Desktop/通讯软件"),
        CodevokeProject("摄影", "/Users/oreo/Desktop/公司/摄影"),
        CodevokeProject("skills-export", "/Users/oreo/Desktop/skills-export"),
    )

    val sessions = listOf(
        CodevokeSession("你好", "—", selected = true),
        CodevokeSession("远程设备接入", "昨天"),
        CodevokeSession("Android Compose", "草稿"),
    )

    val models = listOf(
        CodevokeModel("Opus 4.6", "点击选择模型", selected = true),
        CodevokeModel("Opus 4.7", "claude-opus-4-7"),
        CodevokeModel("Sonnet 4.5", "快速响应"),
    )

    val files = listOf(
        CodevokeFileEntry("后端", "文件夹"),
        CodevokeFileEntry("设计图", "文件夹"),
        CodevokeFileEntry("CodevokeIOS", "文件夹"),
        CodevokeFileEntry("build", "文件夹"),
    )

    val devices = listOf(
        CodevokeDevice("oreo's MacBook Pro", "macOS", online = true),
    )

    val messages = listOf(
        CodevokeMessage(
            text = "**Considering a greeting in Chinese**\n\nI feel like I should come up with a nice greeting in Chinese. Since I don't have any tools at my disposal, I need to think of something that feels friendly and warm.",
            fromUser = false,
            secondary = "reasoning"
        ),
        CodevokeMessage("你好，我在。需要我帮你看代码、修 bug、改功能，还是先梳理一下当前项目状态？", fromUser = false),
        CodevokeMessage("你是什么模型", fromUser = true),
        CodevokeMessage("我是 Claude Opus 4.7，当前模型 ID 是 `claude-opus-4-7`。", fromUser = false),
        CodevokeMessage("实际是啥模型", fromUser = true),
        CodevokeMessage("实际运行的模型是 **Claude Opus 4.7**，模型 ID：`claude-opus-4-7`。", fromUser = false),
    )
}
