import path from 'node:path';
import process from 'node:process';
import ts from 'typescript';

const repoRoot = process.cwd();
const normalizedRepoRoot = normalizePath(repoRoot);
const configPath = ts.findConfigFile(repoRoot, ts.sys.fileExists, 'tsconfig.json');

if (!configPath) {
  throw new Error(`Could not find tsconfig.json from ${repoRoot}`);
}

const configFile = ts.readConfigFile(configPath, ts.sys.readFile);
if (configFile.error) {
  throw new Error(formatDiagnostic(configFile.error));
}

const parsedConfig = ts.parseJsonConfigFileContent(
  configFile.config,
  ts.sys,
  path.dirname(configPath),
  { noEmit: true },
  configPath,
);

if (parsedConfig.errors.length > 0) {
  throw new Error(parsedConfig.errors.map(formatDiagnostic).join('\n'));
}

const sourceFileNames = new Set(
  parsedConfig.fileNames
    .filter((fileName) => fileName.endsWith('.ts') && !fileName.endsWith('.d.ts'))
    .map(normalizePath),
);
const program = ts.createProgram({
  rootNames: [...sourceFileNames],
  options: parsedConfig.options,
});
const checker = program.getTypeChecker();
const languageService = ts.createLanguageService({
  getScriptFileNames: () => [...sourceFileNames],
  getScriptVersion: () => '0',
  getScriptSnapshot: (fileName) => {
    const text = ts.sys.readFile(fileName);
    return text === undefined ? undefined : ts.ScriptSnapshot.fromString(text);
  },
  getCurrentDirectory: () => repoRoot,
  getCompilationSettings: () => parsedConfig.options,
  getDefaultLibFileName: (options) => ts.getDefaultLibFilePath(options),
  fileExists: ts.sys.fileExists,
  readFile: ts.sys.readFile,
  readDirectory: ts.sys.readDirectory,
}, ts.createDocumentRegistry());

const candidatesBySymbol = new Map();

for (const sourceFile of getProductionSourceFiles()) {
  collectCandidates(sourceFile);
}

for (const candidate of candidatesBySymbol.values()) {
  collectReferences(candidate);
}

const candidates = [...candidatesBySymbol.values()]
  .filter((candidate) => candidate.references.length <= 1)
  .sort(compareCandidates);
const zeroUse = candidates.filter((candidate) => candidate.references.length === 0);
const oneUse = candidates.filter((candidate) => candidate.references.length === 1);

console.log(`single-use candidate check — ${candidatesBySymbol.size} declarations analyzed`);
console.log(`zero resolved references: ${zeroUse.length}`);
for (const candidate of zeroUse) printCandidate(candidate);
console.log(`one resolved reference: ${oneUse.length}`);
for (const candidate of oneUse) printCandidate(candidate);
if (candidates.length === 0) console.log('single-use candidate check OK — no candidates found.');

function getProductionSourceFiles() {
  return program.getSourceFiles().filter((sourceFile) => {
    const fileName = normalizePath(sourceFile.fileName);
    return sourceFileNames.has(fileName) && !sourceFile.isDeclarationFile;
  });
}

function collectCandidates(sourceFile) {
  const visit = (node) => {
    const candidate = declarationCandidate(node, sourceFile);
    if (candidate) {
      const symbol = canonicalSymbol(checker.getSymbolAtLocation(candidate.nameNode));
      if (symbol) {
        const existing = candidatesBySymbol.get(symbol);
        if (!existing || hasImplementationBody(candidate.node)) {
          const record = existing ?? {
            symbol,
            name: candidate.name,
            kind: candidate.kind,
            node: candidate.node,
            nameNode: candidate.nameNode,
            sourceFile,
            references: [],
            referenceKeys: new Set(),
          };
          if (hasImplementationBody(candidate.node) || !existing) {
            record.name = candidate.name;
            record.kind = candidate.kind;
            record.node = candidate.node;
            record.nameNode = candidate.nameNode;
            record.sourceFile = sourceFile;
          }
          candidatesBySymbol.set(symbol, record);
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
}

function collectReferences(candidate) {
  const position = candidate.nameNode.getStart(candidate.sourceFile);
  const groups = languageService.findReferences(candidate.sourceFile.fileName, position) ?? [];
  for (const group of groups) {
    for (const reference of group.references) {
      const referenceFileName = normalizePath(reference.fileName);
      const referenceFile = program.getSourceFile(reference.fileName)
        ?? program.getSourceFiles().find((sourceFile) => normalizePath(sourceFile.fileName) === referenceFileName);
      if (!referenceFile) continue;
      const isInsideDeclaration = referenceFileName === normalizePath(candidate.sourceFile.fileName)
        && reference.textSpan.start >= candidate.node.getStart(candidate.sourceFile)
        && reference.textSpan.start < candidate.node.end;
      if (isInsideDeclaration) continue;

      const key = `${referenceFileName}:${reference.textSpan.start}`;
      if (candidate.referenceKeys.has(key)) continue;
      candidate.referenceKeys.add(key);
      const referencePosition = referenceFile.getLineAndCharacterOfPosition(reference.textSpan.start);
      candidate.references.push({
        fileName: reference.fileName,
        line: referencePosition.line + 1,
        column: referencePosition.character + 1,
      });
    }
  }
}

function declarationCandidate(node, sourceFile) {
  if (ts.isFunctionDeclaration(node) && node.name && node.parent === sourceFile) {
    return { node, nameNode: node.name, name: node.name.text, kind: 'function' };
  }

  if (ts.isMethodDeclaration(node)
    && node.name
    && (ts.isClassDeclaration(node.parent) || ts.isClassExpression(node.parent))) {
    const name = declarationName(node.name);
    return name ? { node, nameNode: node.name, name, kind: 'method' } : undefined;
  }

  if (ts.isVariableDeclaration(node)
    && node.name
    && ts.isIdentifier(node.name)
    && node.initializer
    && (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))
    && node.parent.parent === sourceFile) {
    return { node, nameNode: node.name, name: node.name.text, kind: 'function variable' };
  }

  return undefined;
}

function declarationName(node) {
  if (ts.isIdentifier(node) || ts.isStringLiteral(node) || ts.isNumericLiteral(node)) return node.text;
  return undefined;
}

function hasImplementationBody(node) {
  return Boolean(node.body);
}

function canonicalSymbol(symbol) {
  if (!symbol) return undefined;
  let current = symbol;
  const seen = new Set();
  while ((current.flags & ts.SymbolFlags.Alias) !== 0 && !seen.has(current)) {
    seen.add(current);
    const aliased = checker.getAliasedSymbol(current);
    if (!aliased || aliased === current) break;
    current = aliased;
  }
  return current;
}

function compareCandidates(left, right) {
  const fileCompare = normalizePath(left.sourceFile.fileName).localeCompare(normalizePath(right.sourceFile.fileName));
  if (fileCompare !== 0) return fileCompare;
  const lineCompare = left.sourceFile.getLineAndCharacterOfPosition(left.node.getStart(left.sourceFile)).line
    - right.sourceFile.getLineAndCharacterOfPosition(right.node.getStart(right.sourceFile)).line;
  if (lineCompare !== 0) return lineCompare;
  return left.name.localeCompare(right.name);
}

function printCandidate(candidate) {
  const position = candidate.sourceFile.getLineAndCharacterOfPosition(candidate.node.getStart(candidate.sourceFile));
  const location = `${displayPath(candidate.sourceFile.fileName)}:${position.line + 1}`;
  const reference = candidate.references[0];
  const referenceText = reference
    ? ` → ${displayPath(reference.fileName)}:${reference.line}:${reference.column}`
    : '';
  console.log(`- ${location} ${candidate.kind} ${candidate.name} [${candidate.references.length}]${referenceText}`);
}

function displayPath(fileName) {
  return path.relative(normalizedRepoRoot, normalizePath(fileName)).replaceAll('\\', '/');
}

function normalizePath(fileName) {
  return path.resolve(fileName).replaceAll('\\', '/');
}

function formatDiagnostic(diagnostic) {
  return ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n');
}
