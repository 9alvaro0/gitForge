import Foundation

/// Sample What's New content: the 1.3.0 notes, for previews only.
extension WhatsNewPresentation {
    static var previewSingle: WhatsNewPresentation {
        WhatsNewPresentation(currentVersion: "1.3.0", previousVersion: "1.2.0",
                             releases: [previewRelease130], source: .launch)
    }

    static var previewAccumulated: WhatsNewPresentation {
        WhatsNewPresentation(currentVersion: "1.3.0", previousVersion: "1.1.1",
                             releases: [previewRelease130, previewRelease120], source: .launch)
    }

    static var previewNoExtras: WhatsNewPresentation {
        var release = previewRelease130
        release.fixes = []
        release.improvements = []
        return WhatsNewPresentation(currentVersion: "1.3.0", previousVersion: nil,
                                    releases: [release], source: .menu)
    }

    private static var previewRelease130: WhatsNewRelease {
        WhatsNewRelease(
            version: "1.3.0",
            highlights: [
                highlight("globe",
                          en: ("In Spanish and Portuguese", "Follows your Mac's language, or pick one in Settings › Language."),
                          es: ("En español y portugués", "Sigue el idioma de tu Mac, o elige uno en Ajustes › Idioma."),
                          pt: ("Em espanhol e português", "Segue o idioma do teu Mac, ou escolhe um em Definições › Idioma.")),
                highlight("arrow.down.circle",
                          en: ("Updates itself", "Downloads new versions in the background and installs them when you quit, or right away with “Restart to Update”."),
                          es: ("Se actualiza solo", "Descarga las nuevas versiones en segundo plano y las instala al salir, o al momento con «Reiniciar para actualizar»."),
                          pt: ("Atualiza-se sozinho", "Descarrega as novas versões em segundo plano e instala-as ao sair, ou de imediato com «Reiniciar para atualizar».")),
                highlight("checkmark.bubble",
                          en: ("Toasts that say what happened", "Commit, fetch, pull and push confirm with a toast, like “Pushed 3 commits to origin/main”."),
                          es: ("Avisos que dicen qué ha pasado", "Commit, fetch, pull y push confirman con un aviso, como «3 commits subidos a origin/main»."),
                          pt: ("Avisos que dizem o que aconteceu", "Commit, fetch, pull e push confirmam com um aviso, como «3 commits enviados para origin/main».")),
            ],
            fixes: [
                LocalizedText(["en": "If an update fails to install, gitForge retries once and then offers a direct download.",
                               "es": "Si una actualización falla, gitForge lo reintenta una vez y luego te ofrece la descarga directa.",
                               "pt-PT": "Se uma atualização falhar, o gitForge tenta outra vez e depois oferece a transferência direta."]),
            ],
            improvements: [
                LocalizedText(["en": "Scrolling in long histories is smoother.",
                               "es": "El scroll en historiales largos va más fluido.",
                               "pt-PT": "O deslocamento em históricos longos é mais fluido."]),
            ]
        )
    }

    private static var previewRelease120: WhatsNewRelease {
        WhatsNewRelease(
            version: "1.2.0",
            highlights: [
                highlight("paintpalette",
                          en: ("Branches in their colour", "Branch chips in History take the colour of their line in the graph."),
                          es: ("Ramas con su color", "Las etiquetas de rama del historial toman el color de su línea en el grafo."),
                          pt: ("Ramos com a sua cor", "As etiquetas de ramo do histórico usam a cor da sua linha no grafo.")),
            ],
            fixes: [],
            improvements: []
        )
    }

    private static func highlight(_ symbol: String,
                                  en: (String, String), es: (String, String), pt: (String, String)) -> WhatsNewHighlight {
        WhatsNewHighlight(symbol: symbol,
                          title: LocalizedText(["en": en.0, "es": es.0, "pt-PT": pt.0]),
                          body: LocalizedText(["en": en.1, "es": es.1, "pt-PT": pt.1]))
    }
}
