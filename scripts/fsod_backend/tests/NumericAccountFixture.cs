// Proves the ORIGINAL Player.List.cs IsUserInLegends comparison contract under
// MySql.Data 8.4 semantics, without a live database.
//
// Mechanism (parent wServer-runtime.log:206): death.accId is INT (pinned
// db/rotmgprod.sql: `accId` int(11) NOT NULL). Upstream called
// rdr.GetString("accId") in all three leaderboard windows (week/month/alltime).
// MySql.Data 6.9.6 coerced numerics to string; 8.4 performs a strict cast and
// throws InvalidCastException, so every new Player ctor failed once the death
// table held even one row (only CREATE_SUCCESS, no stats/world).
//
// The NumericRowReader below reproduces the 8.4 strict GetString contract and
// returns boxed numerics from GetValue exactly as the 8.4 reader does for an
// INT column. PatchedMatch uses the canonical patched expression, which must
// stay text-identical to the three comparison sites in the patched
// wServer/realm/entities/player/Player.List.cs (cross-checked by
// tests/fsod-backend-numeric.test.mjs). SQL, ordering, glow/XP/fame/death math,
// death rows and exception flow are untouched: no catch, no wipe.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;

// Minimal reader surface used by IsUserInLegends: Read/GetOrdinal/GetValue
// plus the strict 8.4 GetString. Rows are boxed exactly as MySql.Data 8.4
// materializes an INT column (System.Int32).
sealed class NumericRowReader
{
    private readonly List<object> rows;
    private int pos = -1;

    public NumericRowReader(IEnumerable<object> rows) { this.rows = new List<object>(rows); }

    public bool Read() { pos++; return pos < rows.Count; }

    public int GetOrdinal(string name)
    {
        if (name != "accId") throw new IndexOutOfRangeException("no such column: " + name);
        return 0;
    }

    public object GetValue(int ordinal) { return rows[pos]; }

    // MySql.Data 8.4 contract: GetString does NOT coerce numerics; a boxed
    // Int32 throws InvalidCastException (the parent log:206 crash). Only a
    // real string column value passes.
    public string GetString(string name)
    {
        object value = rows[pos];
        if (value is string) return (string)value;
        throw new InvalidCastException("Unable to cast object of type '" +
            (value == null ? "null" : value.GetType().ToString()) + "' to type 'System.String'.");
    }
}

static class NumericAccountFixture
{
    // CANONICAL PATCHED EXPRESSION: keep text-identical to the three
    // IsUserInLegends sites in patched Player.List.cs.
    static bool PatchedMatch(NumericRowReader rdr, string accountId)
    {
        if (Convert.ToString(rdr.GetValue(rdr.GetOrdinal("accId")), CultureInfo.InvariantCulture) == accountId) return true;
        return false;
    }

    // ORIGINAL UPSTREAM EXPRESSION: must throw on numeric death.accId under 8.4.
    static bool OriginalMatch(NumericRowReader rdr, string accountId)
    {
        if (rdr.GetString("accId") == accountId) return true;
        return false;
    }

    static int cases;

    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("numeric-accId case failed: " + message);
        cases++;
    }

    // One leaderboard window: negative control plus match/mismatch/empty and
    // type-variance probes through the patched expression.
    static void Window(string label, string accountId)
    {
        // Negative control: the original expression throws InvalidCastException
        // on a boxed numeric accId, reproducing the post-permadeath ctor crash.
        var strict = new NumericRowReader(new object[] { (object)42 });
        strict.Read();
        bool threw = false;
        try { OriginalMatch(strict, accountId); }
        catch (InvalidCastException) { threw = true; }
        Check(threw, label + ": original GetString must throw InvalidCastException on numeric accId");

        // Matching numeric id compares equal with original string semantics.
        var match = new NumericRowReader(new object[] { (object)42 });
        match.Read();
        Check(PatchedMatch(match, "42"), label + ": patched numeric accId matches AccountId");

        // Non-matching numeric rows never match and never throw.
        var miss = new NumericRowReader(new object[] { (object)7, (object)9 });
        bool found = false;
        while (miss.Read()) found = found || PatchedMatch(miss, "42");
        Check(!found, label + ": patched non-matching numeric accIds do not match");

        // Empty window: no rows, no throw, no match (pre-permadeath shape).
        var empty = new NumericRowReader(new object[0]);
        bool any = false;
        while (empty.Read()) any = any || PatchedMatch(empty, "42");
        Check(!any, label + ": patched empty window matches nothing");

        // Type variance: a string-typed accId still matches (no regression if
        // the column ever materializes as text), and the original accepts it.
        var text = new NumericRowReader(new object[] { (object)"42" });
        text.Read();
        Check(PatchedMatch(text, "42"), label + ": patched string accId still matches");
        var textOld = new NumericRowReader(new object[] { (object)"42" });
        textOld.Read();
        Check(OriginalMatch(textOld, "42"), label + ": original string accId control still matches");

        // Boundary id uses full invariant digits, never truncated or grouped.
        var big = new NumericRowReader(new object[] { (object)int.MaxValue });
        big.Read();
        Check(PatchedMatch(big, "2147483647"), label + ": patched boundary accId matches invariant digits");

        // NULL accId cannot throw; it simply does not equal an AccountId.
        var nil = new NumericRowReader(new object[] { DBNull.Value });
        nil.Read();
        Check(!PatchedMatch(nil, "42"), label + ": patched NULL accId matches nothing without throwing");
    }

    public static void Main()
    {
        string[] cultures = new string[] { "", "tr-TR", "ar-EG", "de-DE", "fr-FR", "ja-JP" };
        int used = 0;
        foreach (string name in cultures)
        {
            CultureInfo culture = string.IsNullOrEmpty(name)
                ? CultureInfo.InvariantCulture : new CultureInfo(name);
            Thread.CurrentThread.CurrentCulture = culture;
            Thread.CurrentThread.CurrentUICulture = culture;
            // All three upstream leaderboard windows per culture.
            Window("week[" + (name == "" ? "invariant" : name) + "]", "42");
            Window("month[" + (name == "" ? "invariant" : name) + "]", "42");
            Window("alltime[" + (name == "" ? "invariant" : name) + "]", "42");
            used++;
            // The conversion result must not depend on the ambient locale:
            // identical numeric input yields the identical AccountId string.
            object boxed = (object)42;
            if (Convert.ToString(boxed, CultureInfo.InvariantCulture) != "42")
                throw new Exception("invariant conversion unstable under " + name);
            cases++;
        }
        if (used < 3) throw new Exception("expected at least invariant plus two real cultures");
        Console.WriteLine("compiled-original-numeric-accId: PASS (" + cases + " cases; 3 windows x " + used + " cultures)");
    }
}
