package org.argeo.build;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.StringJoiner;
import java.util.StringTokenizer;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;

import org.eclipse.jdt.core.compiler.CompilationProgress;

import aQute.bnd.osgi.Analyzer;
import aQute.bnd.osgi.Jar;

public class Make {
	private final static String SDK_MK = "sdk.mk";

	final Path execDirectory;
	final Path sdkSrcBase;
	final Path argeoBuildBase;
	final Path sdkBuildBase;
	final Path buildBase;
	final Path a2Output;

	public Make() throws IOException {
		execDirectory = Paths.get(System.getProperty("user.dir"));
		Path sdkMkP = findSdkMk(execDirectory);
		Objects.requireNonNull(sdkMkP, "No " + SDK_MK + " found under " + execDirectory);

		Map<String, String> context = new HashMap<>();
		List<String> sdkMkLines = Files.readAllLines(sdkMkP);
		lines: for (String line : sdkMkLines) {
			StringTokenizer st = new StringTokenizer(line, " :=");
			if (!st.hasMoreTokens())
				continue lines;
			String key = st.nextToken();
			if (!st.hasMoreTokens())
				continue lines;
			String value = st.nextToken();
			context.put(key, value);
		}

		sdkSrcBase = Paths.get(context.computeIfAbsent("SDK_SRC_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		argeoBuildBase = sdkSrcBase.resolve("sdk/argeo-build");

		sdkBuildBase = Paths.get(context.computeIfAbsent("SDK_BUILD_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		buildBase = sdkBuildBase.resolve(sdkSrcBase.getFileName());
		a2Output = sdkBuildBase.resolve("a2");
	}

	/*
	 * ACTIONS
	 */

	void all(Map<String, List<String>> options) throws IOException {
//		List<String> a2Bundles = options.get("--a2-bundles");
//		if (a2Bundles == null)
//			throw new IllegalArgumentException("--a2-bundles must be specified");
//		List<String> bundles = new ArrayList<>();
//		for (String a2Bundle : a2Bundles) {
//			Path a2BundleP = Paths.get(a2Bundle);
//			Path bundleP = a2Output.relativize(a2BundleP.getParent().getParent().resolve(a2BundleP.getFileName()));
//			bundles.add(bundleP.toString());
//		}
//		options.put("--bundles", bundles);
		compile(options);
		bundle(options);
	}

	@SuppressWarnings("restriction")
	void compile(Map<String, List<String>> options) throws IOException {
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> a2Categories = options.getOrDefault("--dep-categories", new ArrayList<>());
		List<String> a2Bases = options.getOrDefault("--a2-bases", new ArrayList<>());
		if (a2Bases.isEmpty()) {
			a2Bases.add(a2Output.toString());
		}

		List<String> compilerArgs = new ArrayList<>();

		Path ecjArgs = argeoBuildBase.resolve("ecj.args");
		compilerArgs.add("@" + ecjArgs);

		// classpath
		if (!a2Categories.isEmpty()) {
			compilerArgs.add("-cp");
			StringJoiner classPath = new StringJoiner(File.pathSeparator);
			for (String a2Base : a2Bases) {
				for (String a2Category : a2Categories) {
					Path a2Dir = Paths.get(a2Base).resolve(a2Category);
					for (Path jarP : Files.newDirectoryStream(a2Dir,
							(p) -> p.getFileName().toString().endsWith(".jar"))) {
						classPath.add(jarP.toString());
					}
				}
			}
			compilerArgs.add(classPath.toString());
		}

		// sources
		for (String bundle : bundles) {
			StringBuilder sb = new StringBuilder();
			sb.append(execDirectory.resolve(bundle).resolve("src"));
			sb.append("[-d");
			compilerArgs.add(sb.toString());
			sb = new StringBuilder();
			sb.append(buildBase.resolve(bundle).resolve("bin"));
			sb.append("]");
			compilerArgs.add(sb.toString());
		}

		// System.out.println(compilerArgs);

		CompilationProgress compilationProgress = new CompilationProgress() {
			int totalWork;
			long currentChunk = 0;

			long chunksCount = 80;

			@Override
			public void worked(int workIncrement, int remainingWork) {
				long chunk = ((totalWork - remainingWork) * chunksCount) / totalWork;
				if (chunk != currentChunk) {
					currentChunk = chunk;
					for (long i = 0; i < currentChunk; i++) {
						System.out.print("#");
					}
					for (long i = currentChunk; i < chunksCount; i++) {
						System.out.print("-");
					}
					System.out.print("\r");
				}
				if (remainingWork == 0)
					System.out.print("\n");
			}

			@Override
			public void setTaskName(String name) {
			}

			@Override
			public boolean isCanceled() {
				return false;
			}

			@Override
			public void done() {
			}

			@Override
			public void begin(int remainingWork) {
				this.totalWork = remainingWork;
			}
		};
		// Use Main instead of BatchCompiler to workaround the fact that
		// org.eclipse.jdt.core.compiler.batch is not exported
		boolean success = org.eclipse.jdt.internal.compiler.batch.Main.compile(
				compilerArgs.toArray(new String[compilerArgs.size()]), new PrintWriter(System.out),
				new PrintWriter(System.err), (CompilationProgress) compilationProgress);
		if (!success) {
			System.exit(1);
		}
	}

	void bundle(Map<String, List<String>> options) throws IOException {
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> categories = options.get("--category");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (categories.size() != 1)
			throw new IllegalArgumentException("One and only one category must be specified");
		String category = categories.get(0);

		// create jars
		for (String bundle : bundles) {
			createBundle(bundle, category);
		}
	}

	/*
	 * JAR PACKAGING
	 */
	void createBundle(String bundle, String category) throws IOException {
		Path source = execDirectory.resolve(bundle);
		Path compiled = buildBase.resolve(bundle);
		String bundleSymbolicName = source.getFileName().toString();

		// Metadata
		Properties properties = new Properties();
		Path argeoBnd = argeoBuildBase.resolve("argeo.bnd");
		try (InputStream in = Files.newInputStream(argeoBnd)) {
			properties.load(in);
		}
		// FIXME make it configurable
		Path branchBnd = sdkSrcBase.resolve("cnf/unstable.bnd");
		try (InputStream in = Files.newInputStream(branchBnd)) {
			properties.load(in);
		}

		Path bndBnd = source.resolve("bnd.bnd");
		try (InputStream in = Files.newInputStream(bndBnd)) {
			properties.load(in);
		}

		// Normalise
		properties.put("Bundle-SymbolicName", bundleSymbolicName);

		// Calculate MANIFEST
		Path binP = compiled.resolve("bin");
		if (!Files.exists(binP))
			Files.createDirectories(binP);
		Manifest manifest;
		try (Analyzer bndAnalyzer = new Analyzer()) {
			bndAnalyzer.setProperties(properties);
			Jar jar = new Jar(bundleSymbolicName, binP.toFile());
			bndAnalyzer.setJar(jar);
			manifest = bndAnalyzer.calcManifest();

//			keys: for (Object key : manifest.getMainAttributes().keySet()) {
//				System.out.println(key + ": " + manifest.getMainAttributes().getValue(key.toString()));
//			}
		} catch (Exception e) {
			throw new RuntimeException("Bnd analysis of " + compiled + " failed", e);
		}

		String major = properties.getProperty("MAJOR");
		Objects.requireNonNull(major, "MAJOR must be set");
		String minor = properties.getProperty("MINOR");
		Objects.requireNonNull(minor, "MINOR must be set");

		// Write manifest
		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
		Files.createDirectories(manifestP.getParent());
		try (OutputStream out = Files.newOutputStream(manifestP)) {
			manifest.write(out);
		}
//		
//		// Load manifest
//		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
//		if (!Files.exists(manifestP))
//			throw new IllegalStateException("Manifest " + manifestP + " not found");
//		Manifest manifest;
//		try (InputStream in = Files.newInputStream(manifestP)) {
//			manifest = new Manifest(in);
//		} catch (IOException e) {
//			throw new IllegalStateException("Cannot read manifest " + manifestP, e);
//		}

		// Load excludes
		List<PathMatcher> excludes = new ArrayList<>();
		Path excludesP = argeoBuildBase.resolve("excludes.txt");
		for (String line : Files.readAllLines(excludesP)) {
			PathMatcher pathMatcher = excludesP.getFileSystem().getPathMatcher("glob:" + line);
			excludes.add(pathMatcher);
		}

		Path bundleParent = Paths.get(bundle).getParent();
		Path a2JarDirectory = bundleParent != null ? a2Output.resolve(bundleParent).resolve(category)
				: a2Output.resolve(category);
		Path jarP = a2JarDirectory.resolve(compiled.getFileName() + "." + major + "." + minor + ".jar");
		Files.createDirectories(jarP.getParent());

		try (JarOutputStream jarOut = new JarOutputStream(Files.newOutputStream(jarP), manifest)) {
			// add all classes first
//			Path binP = compiled.resolve("bin");
			Files.walkFileTree(binP, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry(binP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

			// add resources
			Files.walkFileTree(source, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(dir);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.SKIP_SUBTREE;

					return FileVisitResult.CONTINUE;
				}

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(file);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.CONTINUE;
					JarEntry entry = new JarEntry(relativeP.toString());
					jarOut.putNextEntry(entry);
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}

			});

			// add sources
			// TODO add effective BND, Eclipse project file, etc., in order to be able to
			// repackage
			Path srcP = source.resolve("src");
			Files.walkFileTree(srcP, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry("OSGI-OPT/src/" + srcP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

		}

	}

	private Path findSdkMk(Path directory) {
		Path sdkMkP = directory.resolve(SDK_MK);
		if (Files.exists(sdkMkP)) {
			return sdkMkP.toAbsolutePath();
		}
		if (directory.getParent() == null)
			return null;
		return findSdkMk(directory.getParent());

	}

	public static void main(String... args) {
		try {
			if (args.length == 0)
				throw new IllegalArgumentException("At least an action must be provided");
			int actionIndex = 0;
			String action = args[actionIndex];
			if (args.length > actionIndex + 1 && !args[actionIndex + 1].startsWith("-"))
				throw new IllegalArgumentException(
						"Action " + action + " must be followed by an option: " + Arrays.asList(args));

			Map<String, List<String>> options = new HashMap<>();
			String currentOption = null;
			for (int i = actionIndex + 1; i < args.length; i++) {
				if (args[i].startsWith("-")) {
					currentOption = args[i];
					if (!options.containsKey(currentOption))
						options.put(currentOption, new ArrayList<>());

				} else {
					options.get(currentOption).add(args[i]);
				}
			}

			Make argeoMake = new Make();
			switch (action) {
			case "compile" -> argeoMake.compile(options);
			case "bundle" -> argeoMake.bundle(options);
			case "all" -> argeoMake.all(options);

			default -> throw new IllegalArgumentException("Unkown action: " + action);
			}

			long jvmUptime = ManagementFactory.getRuntimeMXBean().getUptime();
			System.out.println("Completed after " + jvmUptime + " ms");
		} catch (Exception e) {
			e.printStackTrace();
			System.exit(1);
		}
	}
}
