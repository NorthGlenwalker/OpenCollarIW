////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                              OpenCollar - rlvtpIW                              //
//                                 version 3.992                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to Second Life® //
// and other virtual metaverse environments.  ->  www.opencollar.at/license.html  //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2014  Individual Contributors and OpenCollar - submission set free™ //
// ------------------------------------------------------------------------------ //
//          github.com/OpenCollar/OpenCollarHypergrid/tree/inworldz               //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////
//added back in to handle TP to from owners hud and LM's dropped into collar
key g_kLMID;//store the request id here when we look up  a LM
key lmkMenuID;
string CTYPE = "collar";
list g_lOwners;
string g_sParentMenu = "RLV";
string g_sSubMenu = "TP to";
key g_kWearer;

//MESSAGE MAP
integer COMMAND_OWNER = 500;
integer COMMAND_WEARER = 503;
integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer RLV_CMD = 6000;
integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;

string UPMENU = "BACK";
string g_sScript;

Notify(key kID, string sMsg, integer iAlsoNotifyWearer)
{
    if (kID == g_kWearer)
        llOwnerSay(sMsg);
    else
    {
        llInstantMessage(kID, sMsg);
        if (iAlsoNotifyWearer)
            llOwnerSay(sMsg);
    }
}

key Dialog(key kRCPT, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth)
{
    key kID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|" 
    + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kID);
    return kID;
} 

LandmarkMenu(key kAv, integer iAuth)
{
    list lButtons;
    //put all LMs button list, unless their sNames are >23 chars long, in which case complain
    integer n;
    integer iStop = llGetInventoryNumber(INVENTORY_LANDMARK);
    for (n = 0; n < iStop; n++)
    {
        string sName = llGetInventoryName(INVENTORY_LANDMARK, n);
        lButtons += [sName];
    }

    lmkMenuID = Dialog(kAv, "\n\nChoose a landmark to teleport to.\n Use <pre>tpto <LM name> to TP to a LM.", lButtons, [UPMENU], 0, iAuth);
}

integer UserCommand(integer iNum, string sStr, key kID)
{
    if (iNum < COMMAND_OWNER || iNum > COMMAND_WEARER) return FALSE;
    if (sStr == "runaway" && (kID == g_kWearer || iNum == COMMAND_WEARER))
        llResetScript();
    if (sStr == "menu " + g_sSubMenu || llToLower(sStr) == "tp")
        LandmarkMenu(kID, iNum);
    else if (llSubStringIndex(sStr, "tpto ") == 0)//changed from tp as conflicting with bookmarks
    {
        //we got a "tpto" command with an argument after it.  See if it corresponds to a LM in inventory.
        list lParams = llParseString2List(sStr, [" "], []);
        string sDest = llToLower(llList2String(lParams, 1));
        integer i=0;
        integer m=llGetInventoryNumber(INVENTORY_LANDMARK);
        string s;
        integer found=FALSE;
        for (i=0;i<m;i++)
        {
            s=llGetInventoryName(INVENTORY_LANDMARK,i);
            if (sDest==llToLower(s))
            {  //tp there
                g_kLMID = llRequestInventoryData(s);
                found=TRUE;
            }
        }
        if (!found)
        {
            Notify(kID,"The landmark '"+llList2String(lParams, 1)+"' has not been found in the " + CTYPE + " of "+llKey2Name(g_kWearer)+".",FALSE);
        }
    }
    else
    {
        //do simple pass through for chat commands
        list items = llParseString2List(sStr, [","], []);
        integer n;
        integer iStop = llGetListLength(items);
        integer iChange = FALSE;//set this to true if we see a setting that concerns us
        for (n = 0; n < iStop; n++)
        {   //split off the parameters (anything after a : or =)
            //and see if the thing being set concerns us
            string sThisItem = llList2String(items, n);
            string sBehavior = llList2String(llParseString2List(sThisItem, ["=", ":"], []), 0);
            if (sBehavior == "tpto")
                llMessageLinked(LINK_SET, RLV_CMD, sThisItem, NULL_KEY);
        }
    }
    return TRUE;
}

default
{
    on_rez(integer iParam)
    {
        llResetScript();
    }

    state_entry()
    {
        g_kWearer = llGetOwner();
        g_sScript = llStringTrim(llList2String(llParseString2List(llGetScriptName(), ["-"], []), 1), STRING_TRIM) + "_";
    }

    link_message(integer iSender, integer iNum, string sStr, key kID)
    {
        if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
            llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, NULL_KEY);
        else if (UserCommand(iNum, sStr, kID)) 
            return;
        else if (iNum == DIALOG_RESPONSE)
        {
            if (kID == lmkMenuID)
            {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                key kAv = (key)llList2String(lMenuParams, 0);
                string sMessage = llList2String(lMenuParams, 1);
                integer iPage = (integer)llList2String(lMenuParams, 2);
                integer iAuth = (integer)llList2String(lMenuParams, 3);
                //got a response to the LM menu.
                if (sMessage == UPMENU)
                    llMessageLinked(LINK_SET, iAuth, "menu " + g_sParentMenu, kAv);
                else if (llGetInventoryType(sMessage) == INVENTORY_LANDMARK)
                {
                    UserCommand(iAuth, "tp " + sMessage, kAv);
                    LandmarkMenu(kAv, iAuth);
                }
            }
        }
    }

    dataserver(key kID, string sData)
    {
        if (kID == g_kLMID)
        {
            //we just got back LM data from a "tpto " command.  now do a rlv "tpto" there
            vector vGoTo = (vector)sData + llGetRegionCorner();
            string sCmd = "tpto:";
            sCmd += llDumpList2String([vGoTo.x, vGoTo.y, vGoTo.z], "/");//format the destination in form x/y/z, as rlv requires
            sCmd += "=force";
            llMessageLinked(LINK_SET, RLV_CMD, sCmd, NULL_KEY);
        }
    }
}