import LassoCLI

@main
@available(macOS 15, *)
struct Lasso {
    static func main() async {
        await LassoCommand.main()
    }
}
