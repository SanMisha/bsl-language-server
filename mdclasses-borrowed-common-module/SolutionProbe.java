import com.github._1c_syntax.bsl.mdclasses.CF;
import com.github._1c_syntax.bsl.mdclasses.MDCReadSettings;
import com.github._1c_syntax.bsl.mdclasses.MDClasses;
import com.github._1c_syntax.bsl.mdo.MD;
import com.github._1c_syntax.bsl.mdo.Module;
import com.github._1c_syntax.bsl.mdo.ModuleOwner;
import com.github._1c_syntax.bsl.types.MdoReference;

import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Читает каталог через MDClasses.createSolution (с теми же настройками, что BSL LS) и печатает,
 * что о каждом BSL-файле знают решение и само расширение, и модули объектов в слитой конфигурации.
 * Аргумент: каталог примера (with-base-bsl или without-base-bsl).
 */
public class SolutionProbe {

  private static final String BORROWED_MODULE = "cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl";

  public static void main(String[] args) throws IOException {
    var root = Path.of(args[0]).toAbsolutePath().normalize();
    var solution = MDClasses.createSolution(root, MDCReadSettings.builder().skipDataCompositionSchema(true).build());
    var extension = solution.getExtensions().get(0);

    var location = String.valueOf(MDClasses.class.getProtectionDomain().getCodeSource().getLocation());
    var jarName = Pattern.compile("mdclasses-[^/!]+\\.jar").matcher(location);
    out("mdclasses: " + (jarName.find() ? jarName.group() : location));
    out("Основа: " + solution.getBaseConfiguration().getName() + ", расширение: " + extension.getName());
    out(String.format("%-52s %-34s %-20s %s", "Файл", "Solution.findChild(uri)", "getModuleTypeByURI", "расширение.findChild(uri)"));
    List<Path> files;
    try (Stream<Path> stream = Files.walk(root)) {
      files = stream.filter(p -> p.toString().endsWith(".bsl")).sorted().toList();
    }
    for (var file : files) {
      var uri = file.toUri();
      out(String.format("%-52s %-34s %-20s %s", root.relativize(file), ref(solution, uri),
        solution.getModuleTypeByURI(uri), ref(extension, uri)));
    }

    out("Модули объектов в слитой конфигурации, getModules():");
    for (var name : List.of("CommonModule.ОбщийМодуль1", "Document.Документ1")) {
      var owner = (ModuleOwner) solution.findChild(MdoReference.create(name)).orElseThrow();
      var modules = owner.getModules().stream()
        .map(Module::getUri)
        .map(uri -> root.relativize(Path.of(uri)) + (Files.exists(Path.of(uri)) ? "" : " (файла нет)"))
        .collect(Collectors.joining(", "));
      out("  " + name + ": " + modules);
    }

    var uri = root.resolve(BORROWED_MODULE).toUri();
    var reproduced = solution.findChild(uri).isEmpty() && extension.findChild(uri).isPresent();
    out("Итог: " + (reproduced
      ? "решение не знает " + BORROWED_MODULE + ", а расширение знает — ошибка воспроизводится"
      : "решение знает " + BORROWED_MODULE + " — ошибка не воспроизводится"));
  }

  private static String ref(CF cf, URI uri) {
    return cf.findChild(uri).map(MD::getMdoRef).orElse("—");
  }

  private static void out(String line) {
    System.out.println("| " + line);
  }
}
