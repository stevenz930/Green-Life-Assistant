//
//  ActivityView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

struct ActivityView: View {
    @State private var tags: [String] = ["All", "EPD.Gov.HK", "Earth911", "State of the Planet"]
    @State private var selectedTag: String = "All"
    
    @State private var manager = RSSManager()
    
    let feeds = [
        "https://www.epd.gov.hk/epd/tc_chi/rss_feeds/what_new.xml": "EPD.Gov.HK",
        "https://earth911.com/feed/": "Earth911",
        "https://news.climate.columbia.edu/feed/": "State of the Planet"
    ]
    
    var filteredItems: [RSSItem] {
        if selectedTag == "All" {
            return manager.allItems
        } else {
            return manager.allItems.filter { $0.sourceTag == selectedTag }
        }
    }
    
    @State private var selectedDetailItem: RSSItem?
    
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: - RSS
                ScrollView {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack{
                                // MARK: - Card Background
                                if index == 0 {
                                    HStack{
                                        Spacer()
                                        Image(systemName: "leaf.fill")
                                            .font(.system(size: 80))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                } else {
                                    FlowingGradientBackgroundView(colors: [Color("LushDeep"), Color("Lush"), Color("LushDeep")])
                                        .mask {
                                            HStack{
                                                Spacer()
                                                Image(systemName: "leaf.fill")
                                                    .font(.system(size: 80))
                                            }
                                        }
                                }
                                
                                // MARK: - Card Content
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                        .font(index == 0 ? .title2 : .headline).bold()
                                        .foregroundColor(index == 0 ? .white : .black)
                                    
                                    Spacer()
                                    
                                    HStack{
                                        VStack{
                                            Text(item.sourceTag)
                                                .font(.caption).bold()
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                        }
                                        .background(.cyan)
                                        .cornerRadius(8)
                                        
                                        Spacer()
                                        
                                        Text(item.pubDate.formatted(.relative(presentation: .named)))
                                            .font(.caption)
                                            .foregroundColor(index == 0 ? .white.opacity(0.8) : .gray)
                                    }
                                }
                                .padding()
                            }
                        }
                        .onTapGesture {
                            selectedDetailItem = item
                        }
                        .frame(height: index == 0 ? 200 : 160)
                        .background{
                            if index == 0 {
                                FlowingGradientBackgroundView(colors: [Color("LushDeep"), Color("Lush"), Color("LushDeep")])
                            } else {
                                Color(uiColor: .secondarySystemBackground)
                            }
                        }
                        .cornerRadius(15)
                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                        .padding(.horizontal)
                        .padding(.vertical, 5)
                    }
                }
                
                // MARK: - Loading
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                        
                        VStack {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading...")
                                .padding(.top)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)
                    }
                }
            }
            // MARK: - Web Detail
            .sheet(item: $selectedDetailItem) { item in
                if let url = item.link.normalizedWebURL {
                    SafariView(url: url)
                } else {
                    Text("Unsupported URL")
                }
            }
            .toolbar{
                // MARK: - Tag Menu
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        ForEach(tags, id: \.self) { tag in
                            Button(tag) {
                                selectedTag = tag
                            }
                        }
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
            }
            .navigationTitle("\(selectedTag)")
            .task {
                isLoading = true
                await manager.fetchAllFeeds(feeds: feeds)
                isLoading = false
            }
            .refreshable {
                await manager.fetchAllFeeds(feeds: feeds)
            }
        }
    }
}

#Preview {
    ActivityView()
}
