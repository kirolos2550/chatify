class PreparedLogExport {
  const PreparedLogExport({
    required this.filePath,
    required this.sourceSessionPaths,
  });

  final String filePath;
  final List<String> sourceSessionPaths;
}
