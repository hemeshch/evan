//
//  AssistantMessageViewMarkdown.swift
//  evanai-mobile
//
//  Use this file after installing MarkdownUI package
//

import SwiftUI
import MarkdownUI

// Enhanced AssistantMessageView with full Markdown support
struct AssistantMessageViewMarkdown: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full markdown rendering with GitHub-style theming
            Markdown(message.content)
                .markdownTheme(.gitHub)
                .markdownTextStyle {
                    FontFamily(.system(.rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(message.timestamp, style: .time)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Custom theme for better integration (optional)
extension Theme {
    static let evanAI = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(15)
        }
        .strong {
            FontWeight(.semibold)
        }
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 8) {
                configuration.label
                    .markdownTextStyle {
                        FontSize(28)
                        FontWeight(.bold)
                    }
                Divider()
            }
            .padding(.bottom, 8)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(22)
                    FontWeight(.semibold)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(18)
                    FontWeight(.medium)
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
        }
        .code {
            FontFamily(.system(.monospaced))
            FontSize(14)
            BackgroundColor(Color(.systemGray6))
        }
        .codeBlock { configuration in
            configuration.label
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .markdownTextStyle {
                    FontFamily(.system(.monospaced))
                    FontSize(13)
                }
        }
        .link {
            ForegroundColor(.blue)
            UnderlineStyle(.single)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
        }
}
