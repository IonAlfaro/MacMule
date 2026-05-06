import SwiftUI

private let colorMap: [String: Color] = [
    "blue": .blue,
    "red": .red,
    "green": .green,
    "orange": .orange,
    "purple": .purple,
    "gray": .gray,
]

struct CategoriesSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var newTitle = ""
    @State private var newColor = "blue"

    var body: some View {
        Form {
            Section("Categories") {
                ForEach(store.categories) { cat in
                    HStack {
                        Circle().fill(colorMap[cat.color, default: .gray]).frame(width: 10)
                        Text(cat.title)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.removeCategory(id: store.categories[index].id)
                    }
                }
            }
            Section("Add") {
                TextField("Name", text: $newTitle)
                Picker("Color", selection: $newColor) {
                    Text("Blue").tag("blue")
                    Text("Red").tag("red")
                    Text("Green").tag("green")
                    Text("Orange").tag("orange")
                    Text("Purple").tag("purple")
                }
                Button("Add") {
                    store.addCategory(title: newTitle, color: newColor)
                    newTitle = ""
                }
            }
        }
    }
}
