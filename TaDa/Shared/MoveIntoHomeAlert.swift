// Asks once, on the Mac and iPhone, whether to move a folder's old layout into "Ta Da".
import SwiftUI
import TaDaCore

extension View {
    /// Shows the move question while `model.offersMove`.
    func moveIntoHomeAlert(_ model: AppModel) -> some View {
        alert("Move Ta Da’s files into “\(Vault.home)”?", isPresented: Binding { model.offersMove } set: { _ in }) {
            Button("Move") {
                model.answerMove()
                Task { await model.moveIntoHome() }
            }
            Button("Not Now", role: .cancel) { model.answerMove() }
        } message: {
            Text("Ta Da now keeps the files it makes in a “\(Vault.home)” folder. This moves \(MoveIntoHomeText.folders(model)) into it, and links written with their paths follow. You can also do this later in Settings ▸ Vault.")
        }
    }
}

enum MoveIntoHomeText {
    /// "tasks/, projects/ and .logbook/".
    static func folders(_ model: AppModel) -> String {
        model.oldLayoutFolders.map { $0 + "/" }.formatted(.list(type: .and))
    }
}
