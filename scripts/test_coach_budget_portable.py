#!/usr/bin/env python3
"""Check real prompts/schemas against their configured budgets without an iOS build."""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "AgenticKeepKeep/Core"


def between(path, start, end):
    text = path.read_text(encoding="utf-8")
    return text[text.index(start):text.index(end)]


def main():
    with tempfile.TemporaryDirectory(prefix="coach-budget-") as directory:
        target = pathlib.Path(directory)
        for source in ["LLM/LLMTypes.swift", "LLM/JSONValue.swift", "LLM/LLMRequestTime.swift",
                       "LLM/FitnessSearchTopic.swift", "Agents/MiloPersona.swift", "Agents/AgentPrompts.swift",
                       "Agents/PersonalKnowledge.swift", "Agents/PersonalLearningAgent.swift", "LLM/LLMClient.swift",
                       "Agents/CoachContextPolicy.swift", "Agents/CoachLifeTypes.swift", "Agents/CoachPluginTools.swift"]:
            shutil.copyfile(CORE / source, target / pathlib.Path(source).name)
        (target / "Context.swift").write_text("import Foundation\n" + between(
            CORE / "Data/Models.swift", "enum ChatRole:", "/// 训练目标") + between(
            CORE / "Agents/AgentModels.swift", "struct CoachTurn:", "struct PlanDraft:"), encoding="utf-8")
        agent = CORE / "Agents/CoachAgent.swift"
        (target / "Agent.swift").write_text("import Foundation\nenum CoachAgent {\n" + between(
            agent, "    static func buildMessages(", "    /// 把模型输出") + between(
            agent, "    static let createPlanTool =", "    // MARK: - 解析工具参数") + "\n}", encoding="utf-8")
        (target / "Tools.swift").write_text("import Foundation\nenum BudgetTools {\n" + between(
            CORE / "Agents/CoachTools.swift", "    static let records =", "\n}\n\n/// A bounded") + "\n}", encoding="utf-8")
        (target / "main.swift").write_text('''import Foundation
var context = CoachContext()
context.planState = String(repeating: "计划", count: 330)
let basic = [BudgetTools.records, BudgetTools.search, BudgetTools.reader]
func check(_ label: String, context: CoachContext, tools: [LLMTool], policy: CoachContextPolicy) throws {
    var messages = CoachAgent.buildMessages(history: [], userMessage: "今天怎么练", context: context)
    messages[0].content += "\\n" + BudgetTools.instructions
    let request = LLMRequest(messages: messages, tools: [CoachAgent.createPlanTool, CoachAgent.adjustPlanTool] + tools)
    let used = policy.tokens(request), available = try policy.inputLimit() - policy.queryResultReserve
    let line = "\\(label): mandatory=\\(used), available=\\(available), query reserve=\\(policy.queryResultReserve), system=\\(messages[0].content.utf8.count)\\n"
    FileHandle.standardError.write(Data(line.utf8))
    for tool in request.tools {
        let bytes = try JSONEncoder().encode(tool.parameters).count + tool.description.utf8.count + tool.name.utf8.count + 64
        FileHandle.standardError.write(Data("\\(tool.name)=\\(bytes)\\n".utf8))
    }
    guard used <= available else { throw CoachContextError.tooLarge }
    try policy.validate(request)
}
var failed = false
do { try check("default", context: context, tools: basic, policy: CoachContextPolicy()) } catch { failed = true }
context.personalContext = PersonalLearningAgent.memoryCapabilities + String(repeating: "用户偏好简短说明。", count: 20)
do { try check("personal skill (service default)", context: context, tools: basic + [PersonalSkillTool.definition], policy: CoachContextPolicy(window: 32768, inputCap: 32768)) } catch { failed = true }
context.lifeContext = String(repeating: "用户已确认的训练时段与限制。", count: 50)
let plugins = CoachPluginTools.definitions(enabled: Set(CoachPlugin.allCases), calendarReady: true, alarmReady: true, musicReady: true)
do { try check("all plugins", context: context, tools: basic + plugins + [PersonalSkillTool.definition], policy: CoachContextPolicy(window: 32768, inputCap: 32768)) } catch { failed = true }
if failed { exit(1) }
''', encoding="utf-8")
        executable = target / "budget-probe"
        subprocess.run(["swiftc", *map(str, target.glob("*.swift")), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
