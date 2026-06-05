package com.acode.android.data

data class AcodeProject(
    val name: String,
    val path: String,
    val selected: Boolean = false,
)

data class AcodeSession(
    val title: String,
    val subtitle: String,
    val selected: Boolean = false,
)

data class AcodeModel(
    val title: String,
    val subtitle: String,
    val selected: Boolean = false,
)

data class AcodeFileEntry(
    val name: String,
    val type: String,
)

data class AcodeDevice(
    val name: String,
    val platform: String,
    val online: Boolean,
)

data class AcodeMessage(
    val text: String,
    val fromUser: Boolean,
    val secondary: String? = null,
)

object SampleData {
    val projects = listOf(
        AcodeProject("ClaudeMac", "/Users/oreo/Desktop/ClaudeMac", selected = true),
        AcodeProject("通讯软件", "/Users/oreo/Desktop/通讯软件"),
        AcodeProject("摄影", "/Users/oreo/Desktop/公司/摄影"),
        AcodeProject("skills-export", "/Users/oreo/Desktop/skills-export"),
    )

    val sessions = listOf(
        AcodeSession("你好", "—", selected = true),
        AcodeSession("远程设备接入", "昨天"),
        AcodeSession("Android Compose", "草稿"),
    )

    val models = listOf(
        AcodeModel("Opus 4.6", "点击选择模型", selected = true),
        AcodeModel("Opus 4.7", "claude-opus-4-7"),
        AcodeModel("Sonnet 4.5", "快速响应"),
    )

    val files = listOf(
        AcodeFileEntry("后端", "文件夹"),
        AcodeFileEntry("设计图", "文件夹"),
        AcodeFileEntry("AcodeIOS", "文件夹"),
        AcodeFileEntry("build", "文件夹"),
    )

    val devices = listOf(
        AcodeDevice("oreo's MacBook Pro", "macOS", online = true),
    )

    val messages = listOf(
        AcodeMessage(
            text = "**Considering a greeting in Chinese**\n\nI feel like I should come up with a nice greeting in Chinese. Since I don't have any tools at my disposal, I need to think of something that feels friendly and warm.",
            fromUser = false,
            secondary = "reasoning"
        ),
        AcodeMessage("你好，我在。需要我帮你看代码、修 bug、改功能，还是先梳理一下当前项目状态？", fromUser = false),
        AcodeMessage("你是什么模型", fromUser = true),
        AcodeMessage("我是 Claude Opus 4.7，当前模型 ID 是 `claude-opus-4-7`。", fromUser = false),
        AcodeMessage("实际是啥模型", fromUser = true),
        AcodeMessage("实际运行的模型是 **Claude Opus 4.7**，模型 ID：`claude-opus-4-7`。", fromUser = false),
    )
}
