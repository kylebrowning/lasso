import ArgumentParser
import GrantivaCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check environment and dependencies."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let checks = await DoctorRunner().runAllChecks()

        if options.json {
            print(try JSONOutput.string(checks))
        } else {
            print(DoctorFormatter().format(checks))
        }
    }
}
