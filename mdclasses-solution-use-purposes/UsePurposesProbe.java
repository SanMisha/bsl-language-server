import com.github._1c_syntax.bsl.mdclasses.CF;
import com.github._1c_syntax.bsl.mdclasses.MDCReadSettings;
import com.github._1c_syntax.bsl.mdclasses.MDClasses;

import java.nio.file.Path;

/**
 * Читает каталог через MDClasses.createSolution с теми же настройками, что BSL LS
 * (skipDataCompositionSchema), и печатает корневые свойства основы, каждого расширения
 * и решения: getUsePurposes(), getDefaultRunMode(), getCompatibilityMode().
 * Solution отдаёт эти свойства из слитой конфигурации (getMergedConfiguration()).
 * Аргументы: один или несколько каталогов.
 */
public class UsePurposesProbe {

  public static void main(String[] args) {
    for (var arg : args) {
      var root = Path.of(arg).toAbsolutePath().normalize();
      var solution = MDClasses.createSolution(root, MDCReadSettings.builder().skipDataCompositionSchema(true).build());
      out("Каталог " + root.getFileName());
      var base = solution.getBaseConfiguration();
      out(base.isEmpty() ? "  основа:     нет (Configuration.EMPTY)" : describe("  основа:    ", base));
      for (var extension : solution.getExtensions()) {
        out(describe("  расширение:", extension));
      }
      out(describe("  Solution:  ", solution));
      var lost = solution.getUsePurposes().isEmpty() && solution.getExtensions().stream()
        .anyMatch(extension -> !extension.getUsePurposes().isEmpty());
      out("  Итог: " + (lost
        ? "у расширения назначение задано, у решения список пуст"
        : "назначение у решения совпадает с исходным"));
    }
  }

  private static String describe(String label, CF cf) {
    var compatibility = cf.getCompatibilityMode();
    return label + " " + cf.getName()
      + ": usePurposes=" + cf.getUsePurposes().stream().map(Enum::name).toList()
      + ", defaultRunMode=" + cf.getDefaultRunMode().name()
      + ", compatibilityMode=8." + compatibility.getMinor() + "." + compatibility.getVersion();
  }

  private static void out(String line) {
    System.out.println("| " + line);
  }
}
