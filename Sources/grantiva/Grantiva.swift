import GrantivaCLI

@main
@available(macOS 15, *)
struct Grantiva {
    static func main() async {
        await GrantivaCommand.main()
    }
}
