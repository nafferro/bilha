import Foundation

/// Language of the app: follows the iPhone by default, or a fixed choice.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, pt, en

    static let storageKey = "language"

    var id: String { rawValue }

    /// Shown in the picker. Language names are written in their own language.
    var label: String {
        switch self {
        case .system: L("Automatic")
        case .pt: "Português"
        case .en: "English"
        }
    }

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// The language actually used (Automatic resolved against the iPhone's settings).
    static var current: AppLanguage {
        let s = selected
        guard s == .system else { return s }
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("pt") ? .pt : .en
    }

    static var locale: Locale {
        current == .pt ? Locale(identifier: "pt_PT") : Locale(identifier: "en_GB")
    }
}

/// Translates an English UI string. `%@` placeholders are filled from `args`.
func L(_ english: String, _ args: CVarArg...) -> String {
    let text = AppLanguage.current == .pt ? (Portuguese.strings[english] ?? english) : english
    return args.isEmpty ? text : String(format: text, locale: AppLanguage.locale, arguments: args)
}

extension Date {
    /// "1 hour ago" / "há 1 hora", in the app's language.
    var relativeText: String {
        formatted(.relative(presentation: .named).locale(AppLanguage.locale))
    }

    func text(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(AppLanguage.locale))
    }
}

/// Portuguese (Portugal), keyed by the English text.
enum Portuguese {
    static let strings: [String: String] = [
        // Language
        "Language": "Idioma",
        "Automatic": "Automático",

        // Bottle list
        "Bottles": "Garrafas",
        "Read": "Ler",
        "Remove": "Remover",
        "Add a bottle": "Adicionar garrafa",
        "Touch and hold a bottle to remove it.": "Mantém o dedo numa garrafa para a remover.",
        "Add your Pluma": "Adiciona a tua Pluma",
        "Put the iPhone next to the bottle and add it by Bluetooth.":
            "Põe o iPhone ao lado da garrafa e adiciona-a por Bluetooth.",
        "Reading…": "A ler…",
        "Last reading failed": "A última leitura falhou",
        "Not read yet": "Ainda não foi lida",
        "Read %@": "Lida %@",
        "Remove %@?": "Remover %@?",
        "this bottle": "esta garrafa",
        "Its readings are deleted from this iPhone. You can add it again later.":
            "As leituras dela são apagadas deste iPhone. Podes voltar a adicioná-la mais tarde.",

        // Bottle screen
        "Bottle removed": "Garrafa removida",
        "Last read": "Última leitura",
        "Never": "Nunca",
        "Readings": "Leituras",
        "Rename": "Mudar o nome",
        "Remove bottle": "Remover garrafa",
        "Rename bottle": "Mudar o nome da garrafa",
        "Save": "Guardar",
        "Cancel": "Cancelar",
        "For example, Kitchen or Barbecue. Leave it empty to use its Bluetooth name.":
            "Por exemplo, Cozinha ou Churrasco. Deixa vazio para usar o nome Bluetooth.",
        "Read bottle": "Ler garrafa",
        "Reading another bottle…": "A ler outra garrafa…",
        "Looking for the bottle…": "À procura da garrafa…",
        "Connecting…": "A ligar…",
        "Bluetooth is off": "Bluetooth desligado",

        // Readings and events
        "Read the bottle in the Galp app, then here, and type in the Galp app's %. A few of these are enough to confirm what each value means.":
            "Lê a garrafa na app Galp, depois aqui, e escreve o % que a app Galp mostrou. Bastam algumas leituras destas para confirmar o que cada valor quer dizer.",
        "Bilha readings": "Leituras Bilha",
        "No readings yet": "Ainda não há leituras",
        "Read the bottle from its screen.": "Lê a garrafa no ecrã dela.",
        "What did the Galp app show?": "Quanto mostrava a app Galp?",
        "Gas %": "Gás %",

        // Adding a bottle
        "Nearby Plumas": "Plumas por perto",
        "Turn on Bluetooth and allow this app to use it.": "Liga o Bluetooth e deixa esta app usá-lo.",
        "Looking for Plumas… Put the iPhone right next to the bottle.":
            "À procura de Plumas… Encosta o iPhone à garrafa.",
        "Tap your bottle. The closest one is at the top.": "Toca na tua garrafa. A mais próxima aparece em primeiro.",
        "Very close": "Muito perto",
        "Close": "Perto",
        "Far": "Longe",

        // Reading
        "The bottle didn't send a reading. Try again.": "A garrafa não enviou leitura. Tenta outra vez.",

        "Temperature": "Temperatura",
        "Gas left": "Gás restante",
        // Reading errors
        "Couldn't find a Pluma right next to the iPhone. Put the iPhone against the bottle and try again. The Bluetooth log lists the devices it saw.":
            "Não encontrei nenhuma Pluma junto ao iPhone. Encosta o iPhone à garrafa e tenta outra vez. O registo Bluetooth mostra os aparelhos que apareceram.",
        "The bottle didn't answer. Bring the phone closer and try again.":
            "A garrafa não respondeu. Aproxima o iPhone e tenta outra vez.",
        "Couldn't connect: %@": "Não foi possível ligar: %@",
        "unknown error": "erro desconhecido",
        "The bottle disconnected before the reading finished.": "A garrafa desligou-se antes de a leitura acabar.",
        "The bottle has no services.": "A garrafa não tem serviços Bluetooth.",
        "This doesn't look like a Pluma bottle (no command channel).":
            "Isto não parece uma garrafa Pluma (não tem canal de comandos).",
    ]
}
