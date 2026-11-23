// devin-chinese-thinking — Devin 生命周期 hook（官方 hooks 机制）
// 在 SessionStart 与 UserPromptSubmit 时向 Agent 上下文注入语言指令。
// 仅输出官方约定的 additionalContext，不读写文件、不访问网络。
// 标记：devin-chinese-thinking:v2-hook

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  const event = process.argv[2] || 'UserPromptSubmit';
  const additionalContext = [
    '强制语言规则：从本会话第一轮起，所有内部 reasoning/thinking 都必须使用简体中文，',
    '包括 Devin、SWE-FLASH、SWE-2 及子代理、计划模式和工具调用前的推理。',
    '不要生成英文思考链；若上下文中已有英文思考链，后续推理立即改用简体中文。',
    '代码、命令、文件路径、API 名称等技术标识符保持原文。'
  ].join('');
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: event,
      additionalContext,
    },
  }) + '\n');
});
