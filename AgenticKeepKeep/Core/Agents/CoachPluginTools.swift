import Foundation

enum CoachPluginTools {
    static let life = LLMTool(name: "query_life_context", description: "规划/调整训练前查询生活约束、临时状态、实际训练与健康摘要及未来日历忙闲。最多14天。必须先查再规划，缺失不编造。",
        parameters: JSONSchema.object(properties: ["days": JSONSchema.integer(description: "未来日历天数1–14，默认7")], required: []))
    static let calendar = LLMTool(name: "query_calendar", description: "查询所选日历及可用时段。返回事件临时代号，用于明确定位；不读备注或参会人。",
        parameters: JSONSchema.object(properties: ["start": JSONSchema.string(description: "开始时间，带时区的ISO8601"), "end": JSONSchema.string(description: "结束时间，带时区ISO8601；最多31天")], required: ["start", "end"]))
    static let calendarChange = LLMTool(name: "propose_calendar_change", description: "提出日历新增/修改/删除卡片，用户确认前不执行。已有事件必须先查询取得eventToken；重复范围由用户选。",
        parameters: JSONSchema.object(properties: [
            "action": JSONSchema.string(description: "操作", enumValues: ["create", "update", "delete"]),
            "eventToken": JSONSchema.string(description: "本次查询事件代号；新增不传"),
            "title": JSONSchema.string(description: "标题"), "start": JSONSchema.string(description: "带时区ISO8601起点"),
            "end": JSONSchema.string(description: "带时区ISO8601终点"), "allDay": .object(["type": .string("boolean")]),
            "location": JSONSchema.string(description: "用户指定地点"), "reminderMinutes": JSONSchema.integer(description: "提前提醒分钟0–10080"),
            "recurrence": JSONSchema.string(description: "仅新建时可指定重复", enumValues: ["none", "daily", "weekly"]),
            "repeatUntil": JSONSchema.string(description: "重复结束日期，带时区ISO8601，最多一年"),
            "reason": JSONSchema.string(description: "本次变化的依据")
        ], required: ["action"]))
    static let alarms = LLMTool(name: "query_moveliq_alarms", description: "查询当前账号由Moveliq创建且系统仍安排的闹钟；不读取系统时钟App其他闹钟。",
        parameters: JSONSchema.object(properties: [:], required: []))
    static let alarmChange = LLMTool(name: "propose_alarm_change", description: "提出Moveliq闹钟或N分钟后提醒的确认卡，不直接执行。取消/修改须先查实际alarmID。",
        parameters: JSONSchema.object(properties: [
            "action": JSONSchema.string(description: "操作", enumValues: ["create", "update", "cancel"]),
            "alarmID": JSONSchema.string(description: "已有闹钟UUID，先查"), "title": JSONSchema.string(description: "提醒内容"),
            "date": JSONSchema.string(description: "一次性时间，带时区ISO8601；与周期/倒计时互斥"),
            "time": JSONSchema.string(description: "周期闹钟当地HH:mm"),
            "weekdays": JSONSchema.array(items: JSONSchema.integer(description: "周日1到周六7"), description: "周期星期列表"),
            "countdownMinutes": JSONSchema.integer(description: "1–1440分钟后提醒，与date/time互斥"),
            "reason": JSONSchema.string(description: "用户明确指令/关联训练依据")
        ], required: ["action"]))
    static let places = LLMTool(name: "search_places", description: "按明确地点名称查询地图候选。nearby仅在用户明确需要附近/当前位置时true；不持续定位。",
        parameters: JSONSchema.object(properties: ["query": JSONSchema.string(description: "地点名称，最多200字"), "nearby": .object(["type": .string("boolean")])], required: ["query", "nearby"]))
    static let mapOpen = LLMTool(name: "propose_map_route", description: "为已搜索的地点生成查看路线卡，用户选择后打开Apple地图。不声称已导航/已到达。",
        parameters: JSONSchema.object(properties: ["placeToken": JSONSchema.string(description: "搜索返回的目的地代号"), "startPlaceToken": JSONSchema.string(description: "可选，用户明确提供的起点经搜索后的代号；不传则在Apple地图中选择起点"), "transport": JSONSchema.string(description: "方式", enumValues: ["walking", "driving", "transit", "cycling"])], required: ["placeToken", "transport"]))
    static let music = LLMTool(name: "search_apple_music", description: "搜索歌曲、专辑、歌单；按订阅能力搜索曲库或用户媒体库。用户授权后使用。",
        parameters: JSONSchema.object(properties: ["query": JSONSchema.string(description: "歌名、歌手或歌单名称，不发送整段私人对话")], required: ["query"]))
    static let musicPlay = LLMTool(name: "propose_music_playback", description: "为实际搜索结果生成播放确认卡；会替换系统音乐队列，用户确认前不播放。",
        parameters: JSONSchema.object(properties: ["musicToken": JSONSchema.string(description: "本次搜索返回代号")], required: ["musicToken"]))
    static let musicControl = LLMTool(name: "control_apple_music", description: "查询播放状态；播放/暂停/切歌先生成确认卡，不自动打断其他音频。",
        parameters: JSONSchema.object(properties: ["action": JSONSchema.string(description: "操作", enumValues: ["pause", "resume", "next", "previous", "status"])], required: ["action"]))
    static func definitions(enabled: Set<CoachPlugin>, calendarReady: Bool, alarmReady: Bool, musicReady: Bool) -> [LLMTool] {
        var tools = [life]
        if enabled.contains(.calendar), calendarReady { tools += [calendar, calendarChange] }
        if enabled.contains(.alarms), alarmReady { tools += [alarms, alarmChange] }
        if enabled.contains(.maps) { tools += [places, mapOpen] }
        if enabled.contains(.music), musicReady { tools += [music, musicPlay, musicControl] }
        return tools
    }
}
