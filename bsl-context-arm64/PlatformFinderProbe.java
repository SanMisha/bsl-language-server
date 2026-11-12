import com.github._1c_syntax.bsl.context.PlatformFinder;

public class PlatformFinderProbe {
  public static void main(String[] args) {
    System.out.println("os.name=" + System.getProperty("os.name") + " os.arch=" + System.getProperty("os.arch"));
    System.out.println("findAllInstalls=" + PlatformFinder.findAllInstalls());
    System.out.println("findLatest=" + PlatformFinder.findLatest());
  }
}
