import ArgumentParser

@available(macOS 15, *)
struct UICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "UI automation — tap, swipe, type, screenshot, accessibility.",
        subcommands: [
            TapCommand.self,
            SwipeCommand.self,
            TypeCommand.self,
            ScreenshotCommand.self,
            A11yCommand.self,
        ]
    )
}
