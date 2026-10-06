// FSoD backend bootstrap utility; no reimplemented gameplay or data assignment.
// Uses the ORIGINAL db.dll XmlData loader and its original Dispose persistence.
// Original source revision: 6fd20aad4a7905b13f25389c68368a942a2b68cb, AGPLv3.
using db.data;
using System.IO;
using log4net.Config;

internal static class MetadataIds
{
    private static void Main()
    {
        XmlConfigurator.Configure(new FileInfo("log4net_server.config"));
        using (var data = new XmlData()) { }
    }
}
