﻿////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                             OpenCollar - rlvrelayIW                            //
//                                 version 3.995                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to InWorldz     //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2017  Individual Contributors and OpenCollar Official               //
// ------------------------------------------------------------------------------ //
//          http://github.com/NorthGlenwalker/OpenCollarIW                        //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////

integer RELAY_CHANNEL = -1812221819;
integer g_iRlvListener;

//MESSAGE MAP
integer COMMAND_OWNER = 500;
integer COMMAND_WEARER = 503;
integer COMMAND_RLV_RELAY = 507; // now will be used from rlvrelay to rlvmain, for ping only
integer COMMAND_SAFEWORD = 510;
integer COMMAND_RELAY_SAFEWORD = 511;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
                            //str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer LM_SETTING_DELETE = 2003;

integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.

integer RLV_OFF = 6100; // send to inform plugins that RLV is disabled now, no message or key needed
integer RLV_ON = 6101; // send to inform plugins that RLV is enabled now, no message or key needed

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;

string g_sParentMenu = "RLV";
string g_sSubMenu = "Relay";

string UPMENU = "BACK";

string ALL = " ALL";

key g_kWearer;

key g_kMenuID;
key g_kMinModeMenuID;
key g_kAuthMenuID;
key g_kListMenuID;
key g_kListID;

integer g_iGarbageRate = 60; //garbage collection rate

list g_lSources=[];
list g_lTempWhiteList=[];
list g_lTempBlackList=[];
list g_lTempUserWhiteList=[];
list g_lTempUserBlackList=[];
list g_lObjWhiteList=[];
list g_lObjBlackList=[];
list g_lAvWhiteList=[]; // keys stored as string since strings is what you get when restoring settings
list g_lAvBlackList=[]; // same here (this fixes issue 1253)
list g_lObjWhiteListNames=[];
list g_lObjBlackListNames=[];
list g_lAvWhiteListNames=[];
list g_lAvBlackListNames=[];

integer g_iRLV=FALSE;
list g_lQueue=[];
integer QSTRIDES=3;
integer g_iListener=0;
integer g_iAuthPending = FALSE;
integer g_iRecentSafeword;
string g_sListType;

//relay specific message map
integer CMD_ADDSRC = 11;
integer CMD_REMSRC = 12;

string CTYPE = "collar";
string WEARERNAME;
list g_lCollarOwnersList;
list g_lCollarSecOwnersList;
list g_lCollarBlackList;


//settings
integer g_iMinBaseMode = 0;
integer g_iMinSafeMode = 1;
integer g_iMinLandMode = 0;
integer g_iMinPlayMode = 0;
integer g_iBaseMode = 2;
integer g_iSafeMode = 1;
integer g_iLandMode = 1;
integer g_iPlayMode = 0;

key g_kDebugRcpt = NULL_KEY; // recipient key for relay chat debugging (useful since you cannot eavesdrop llRegionSayTo)
string g_sScript;

// Sanitizes a key coming from the outside, so that only valid
// keys are returned, and invalid ones are mapped to NULL_KEY
key SanitizeKey(string uuid)
{
    if ((key)uuid) return llToLower(uuid);
    return NULL_KEY;
}

string Mode2String(integer iMin)
{
    string sOut;
    if (iMin)
    {
        if (!g_iMinBaseMode)
             sOut+="off";
        else if (g_iMinBaseMode==1)
             sOut+="restricted";
        else if (g_iMinBaseMode==2)
             sOut+="ask";
        else if (g_iMinBaseMode==3)
             sOut+="auto";
        if (!g_iMinSafeMode)
             sOut+=", without safeword";
        else
             sOut+=", with safeword";
        if (g_iMinPlayMode)
             sOut+=", playful";
        else
             sOut+=", not playful";
        if (g_iMinLandMode)
             sOut+=", landowner trusted.";
        else
             sOut+=", landowner not trusted.";
    }
    else
    {
        if (!g_iBaseMode)
             sOut+="off";
        else if (g_iBaseMode==1)
             sOut+="restricted";
        else if (g_iBaseMode==2)
             sOut+="ask";
        else if (g_iBaseMode==3)
             sOut+="auto";
        if (!g_iSafeMode)
             sOut+=", without safeword";
        else
             sOut+=", with safeword";
        if (g_iPlayMode)
             sOut+=", playful";
        else
             sOut+=", not playful";
        if (g_iLandMode)
             sOut+=", landowner trusted.";
        else
             sOut+=", landowner not trusted.";
    }
    return sOut;
}

Notify(key kID, string sMsg, integer iAlsoNotifyWearer)
{
    if (kID == g_kWearer)
         llOwnerSay(sMsg);
    else
    {
        if (llGetAgentSize(kID))
             llRegionSayTo(kID,0,sMsg);
        else
             llInstantMessage(kID, sMsg);
        if (iAlsoNotifyWearer)
             llOwnerSay(sMsg);
    }
}

SaveSettings()
{
    string sNewSettings= g_sScript + "settings=mode:"
        +(string)(512 * g_iMinPlayMode + 256 * g_iMinLandMode + 128 * g_iMinSafeMode + 32 * g_iMinBaseMode
        + 16 * g_iPlayMode + 8 * g_iLandMode + 4 * g_iSafeMode + g_iBaseMode);
    if ( g_lAvWhiteList != [] )
         sNewSettings+=",avwhitelist:"+llDumpList2String(g_lAvWhiteList,"/") +",avwhitelistnames:"+llDumpList2String(g_lAvWhiteListNames,"/");
    if ( g_lAvBlackList != [] )
         sNewSettings+=",avblacklist:"+llDumpList2String(g_lAvBlackList,"/") +",avblacklistnames:"+llDumpList2String(g_lAvBlackListNames,"/");
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, sNewSettings, NULL_KEY);
}

UpdateSettings(string sSettings)
{
    list lArgs = llParseString2List(sSettings,[","],[]);
    integer i;
    for (i=0;i<llGetListLength(lArgs);++i)     // IW PATCH
    {
        list setting=llParseString2List(llList2String(lArgs,i),[":"],[]);
        string var=llList2String(setting,0);
        list vals=llParseString2List(llList2String(setting,1),["/"],[]);
        if (var=="mode")
        {
            integer iMode=llList2Integer(setting,1);
            g_iBaseMode = iMode        & 3;
            g_iSafeMode = (iMode >> 2) & 1;
            g_iLandMode = (iMode >> 3) & 1;
            g_iPlayMode = (iMode >> 4) & 1;
            g_iMinBaseMode = (iMode >> 5) & 3;
            g_iMinSafeMode = (iMode >> 7) & 1;
            g_iMinLandMode = (iMode >> 8) & 1;
            g_iMinPlayMode = (iMode >> 9) & 1;
        }
        else if (var=="avwhitelist")
             g_lAvWhiteList=vals;
        else if (var=="avblacklist")
             g_lAvBlackList=vals;
        else if (var=="avwhitelistnames")
             g_lAvWhiteListNames=vals;
        else if (var=="avblacklistnames")
             g_lAvBlackListNames=vals;
    }
}


integer Auth(key object, key user)
{
    integer iAuth=1;
    key kOwner = llGetOwnerKey(object);
    //object auth
    integer iSourceIndex=llListFindList(g_lSources,[object]);
    if (~iSourceIndex)
    { }
    else if (~llListFindList(g_lTempBlackList+g_lObjBlackList,[object]))
         return -1;
    else if (~llListFindList(g_lAvBlackList,[(string)kOwner]))
         return -1;
    else if (~llListFindList(g_lCollarBlackList,[(string)kOwner]))
         return -1;
    else if (g_iBaseMode==3)
    { }
    else if (g_iLandMode && llGetOwnerKey(object)==llGetLandOwnerAt(llGetPos()))
    { }
    else if (~llListFindList(g_lTempWhiteList+g_lObjWhiteList,[object]))
    { }
    else if (~llListFindList(g_lAvWhiteList,[(string)kOwner]))
    { }
    else if (~llListFindList(g_lCollarOwnersList+g_lCollarSecOwnersList,[(string)kOwner]))
    { }
    else
         iAuth=0;
    if (user)
    {
        if (~llListFindList(g_lAvBlackList+g_lTempUserBlackList,[user]))
             return -1;
        else if (~llListFindList(g_lCollarBlackList,[(string)user]))
             return -1;
        else if (g_iBaseMode == 3)
        { }
        else if (~llListFindList(g_lAvWhiteList+g_lTempUserWhiteList,[user]))
        { }
        else if (~llListFindList(g_lCollarOwnersList+g_lCollarSecOwnersList,[(string)user]))
        { }
        else
            return 0;
    }
    return iAuth;
}

Dequeue()
{
    string sCommand;
    string sCurIdent;
    key kCurID;
    while (sCommand=="")
    {
        if (g_lQueue==[])
        {
            llSetTimerEvent(g_iGarbageRate);
            return;
        }
        sCurIdent=llList2String(g_lQueue,0);
        kCurID=llList2String(g_lQueue,1);
        sCommand=HandleCommand(sCurIdent,kCurID,llList2String(g_lQueue,2),FALSE);
        g_lQueue = llDeleteSubList(g_lQueue, 0, QSTRIDES-1);
    }
    g_lQueue=[sCurIdent,kCurID,sCommand]+g_lQueue;
    list lButtons=["Yes","No","Trust Object","Ban Object","Trust Owner","Ban Owner"];
    string sOwner=llGetDisplayName(llGetOwnerKey(kCurID))+"("+llKey2Name(llGetOwnerKey(kCurID))+")";
    if (sOwner!="")
         sOwner= ", owned by "+sOwner+",";
    string sPrompt=llKey2Name(kCurID)+sOwner+" wants to control your viewer.";
    if (llGetSubString(sCommand,0,6)=="!x-who/")
    {
        lButtons+=["Trust User","Ban User"];
        sPrompt+="\n"+llGetDisplayName(llGetOwnerKey(kCurID))+"("+llKey2Name(llGetOwnerKey(kCurID))+")"+" is currently using this device.";
    }
    sPrompt+="\n\nDo you want to allow this?";
    g_iAuthPending = TRUE;
    g_kAuthMenuID = Dialog(g_kWearer, sPrompt, lButtons, [], 0, COMMAND_WEARER); // should be enough to dequeue...
}

string HandleCommand(string sIdent, key kID, string sCom, integer iAuthed)
{
    list lCommands=llParseString2List(sCom,["|"],[]);
    sCom = llList2String(lCommands, 0);
    integer iGotWho = FALSE; // has the user been specified up to now?
    key kWho;
    integer i;
    for ( i = 0 ; i < llGetListLength(lCommands) ; i++)     // IW PATCH for OC 3.991  What a HORRIBLE OC coding in the first place! Trying to save a few bytes? Pfff!!
    {
        sCom = llList2String(lCommands,i);
        list lSubArgs = llParseString2List(sCom,["="],[]);
        string sVal = llList2String(lSubArgs,1);
        string sAck = "ok";
        if (sCom == "!release" || sCom == "@clear")
             llMessageLinked(LINK_SET,RLV_CMD,"clear",kID);
        else if (sCom == "!version")
            sAck = "1100";
        else if (sCom == "!implversion")
            sAck = "OpenCollar 3.9";
        else if (sCom == "!x-orgversions")
          sAck = "ORG=0003/who=001";
        else if (llGetSubString(sCom,0,6)=="!x-who/")
        {
            kWho = SanitizeKey(llGetSubString(sCom,7,42));
            iGotWho=TRUE;
        }
        else if (llGetSubString(sCom,0,0) == "!")
             sAck = "ko"; // ko unknown meta-commands
        else if (llGetSubString(sCom,0,0) != "@")
        {
            llOwnerSay("Bad RLV relay command from "+llKey2Name(kID)+". \nCommand: "+sIdent+","+(string)g_kWearer+","+llDumpList2String(lCommands,"|")+"\nFaulty subcommand: "+sCom+"\nPlease report to the maker of this device."); //added this after issue 984
            sAck=""; //not ko'ing as some old bug in chorazin cages would make them go wrong. Otherwise "ko" looks closer in spirit to the relay spec. (issue 514)
        }//probably an ill-formed command, not answering
        else if ((!llSubStringIndex(sCom,"@version"))||(!llSubStringIndex(sCom,"@get"))||(!llSubStringIndex(sCom,"@findfolder"))) //(IsChannelCmd(sCom))
        {
            if ((integer)sVal)
                 llMessageLinked(LINK_SET,RLV_CMD, llGetSubString(sCom,1,-1), kID); //now with RLV 1.23, negative channels can also be used
            else
                 sAck="ko";
        }
        else if (g_iPlayMode&&llGetSubString(sCom,0,0)=="@"&&sVal!="n"&&sVal!="add")
           llMessageLinked(LINK_SET,RLV_CMD, llGetSubString(sCom,1,-1), kID);
        else if (!iAuthed)
        {
            if (iGotWho) return "!x-who/"+(string)kWho+"|"+llDumpList2String(llList2List(lCommands,i,-1),"|");
            else return llDumpList2String(llList2List(lCommands,i,-1),"|");
        }
//NG        else if ((lSubArgs!=[])==2)
        else if (llGetListLength (lSubArgs) == 2)
        {
            string sBehav=llGetSubString(llList2String(lSubArgs,0),1,-1);
            if (sVal=="force"||sVal=="n"||sVal=="add"||sVal=="y"||sVal=="rem"||sBehav=="clear")
                llMessageLinked(LINK_SET,RLV_CMD,sBehav+"="+sVal,kID);
            else
                sAck="ko";
        }
        else
        {
            llOwnerSay("Bad RLV relay command from "+llKey2Name(kID)+". \nCommand: "+sIdent+","+(string)g_kWearer+","+llDumpList2String(lCommands,"|")+"\nFaulty subcommand: "+sCom+"\nPlease report to the maker of this device."); //added this after issue 984
            sAck=""; //not ko'ing as some old bug in chorazin cages would make them go wrong. Otherwise "ko" looks closer in spirit to the relay spec. (issue 514)
        }//probably an ill-formed command, not answering
        if (sAck)
            sendrlvr(sIdent, kID, sCom, sAck);
    }
    return "";
}

sendrlvr(string sIdent, key kID, string sCom, string sAck)
{
    llRegionSayTo(kID, RELAY_CHANNEL, sIdent+","+(string)kID+","+sCom+","+sAck);
    if (g_kDebugRcpt == g_kWearer)
         llOwnerSay("From relay: "+sIdent+","+(string)kID+","+sCom+","+sAck);
    else if (g_kDebugRcpt)
         llRegionSayTo(g_kDebugRcpt, DEBUG_CHANNEL, "From relay: "+sIdent+","+(string)kID+","+sCom+","+sAck);
}

SafeWord()
{
    if (g_iSafeMode)
    {
        llMessageLinked(LINK_SET, COMMAND_RELAY_SAFEWORD, "","");
        llOwnerSay("You have safeworded");
        g_lTempBlackList=[];
        g_lTempWhiteList=[];
        g_lTempUserBlackList=[];
        g_lTempUserWhiteList=[];
        integer i;
        for (i=0;i<llGetListLength(g_lSources);++i)     // IW PATCH
            sendrlvr("release", llList2Key(g_lSources, i), "!release", "ok");
        g_lSources=[];
        g_iRecentSafeword = TRUE;
        refreshRlvListener();
        llSetTimerEvent(30.);
    }
    else
    {
        llOwnerSay("Sorry, safewording is disabled now!");
    }
}

//----Menu functions section---//
Menu(key kID, integer iAuth)
{
    string sPrompt;
    list lButtons;
    if(g_iMinBaseMode == 0)//only show is minimode is turned off
    {
        sPrompt = "Pick from 4 base modes - \"Off\", \"Restricted\", \"Ask\", and \"Auto\"";
        lButtons = llDeleteSubList(["Off", "Restricted", "Ask", "Auto"],g_iBaseMode,g_iBaseMode);
    }
    sPrompt += "\nCurrent mode is: " + Mode2String(FALSE);
    if (g_lSources != [])
         lButtons = llDeleteSubList(lButtons,0,0);
    if (!g_iMinPlayMode)
    {
        if (g_iPlayMode)
             lButtons+=["- Playful"];
        else
             lButtons+=["+ Playful"];
    }
    if (!g_iMinLandMode)
    {
        if (g_iLandMode)
             lButtons+=["- Land"];
        else
             lButtons+=["+ Land"];
    }
    if (g_lSources!=[])
    {
        sPrompt+="\n\nCurrently grabbed by "+(string)(g_lSources!=[])+" object";
        if (g_lSources==[1])
             sPrompt+="."; // Note: only list LENGTH is compared here
        else
             sPrompt+="s.";
        lButtons+=["Grabbed by"];
        if (g_iSafeMode)
             lButtons+=["Safeword"];
    }
    else if (kID == g_kWearer && !g_iMinSafeMode)
    {
        if (g_iSafeMode)
             lButtons+=["- Safeword"];
        else
             lButtons+=["+ Safeword"];
    }
    if (g_lQueue!=[])
    {
        sPrompt+="\n\nYou have pending requests.";
        lButtons+=["Pending"];
    }
    lButtons+=["Access Lists", "MinMode"];
    if(g_iMinBaseMode != 0 || g_iMinPlayMode || g_iMinLandMode || g_iMinSafeMode)
        sPrompt+="\nSome restrictions have been set in MinMode";
    sPrompt+="\n\nMake a choice:";

    g_kMenuID = Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth);
}

MinModeMenu(key kID, integer iAuth)
{
    list lButtons = llDeleteSubList(["Off", "Restricted", "Ask", "Auto"],g_iMinBaseMode,g_iMinBaseMode);
    string sPrompt = "Current minimal authorized relay mode is: " + Mode2String(TRUE);
    if (g_iMinPlayMode)
         lButtons+=["- Playful"];
    else
         lButtons+=["+ Playful"];
    if (g_iMinLandMode)
         lButtons+=["- Land"];
    else
         lButtons+=["+ Land"];
    if (g_iMinSafeMode)
         lButtons+=["- Safeword"];
    else
         lButtons+=["+ Safeword"];
    sPrompt+="\nAny setting showing as a \"-\" can not be changed in main menu\nChoose a new minimal mode (forces ) the wearer won't be allowed to change.\n(owner only)";
    g_kMinModeMenuID = Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth);
}

ListsMenu(key kID, integer iAuth)
{
    string sPrompt="\n\nWhat list do you want to remove items from?";
    list lButtons=["Trusted Object","Banned Object","Trusted Avatar","Banned Avatar",UPMENU];
    sPrompt+="\n\nMake a choice:";
    g_kListMenuID = Dialog(kID, sPrompt, lButtons, [], 0, iAuth);
}

PListsMenu(key kID, string sMsg, integer iAuth)
{
    list lOList;
    list lOListNames;
    string sPrompt;
    if (sMsg==UPMENU)
    {
        Menu(kID, iAuth);
        return;
    }
    else if (sMsg=="Trusted Object")
    {
        lOList=g_lObjWhiteList;
        lOListNames=g_lObjWhiteListNames;
        sPrompt="\n\nWhat object do you want to stop trusting?";
        if (lOListNames == [])
             sPrompt+="\n\nNo object in list.";
        else
             sPrompt+="\n\nObserve chat for the list.";
    }
    else if (sMsg=="Banned Object")
    {
        lOList=g_lObjBlackList;
        lOListNames=g_lObjBlackListNames;
        sPrompt="\n\nWhat object do you want not to ban anymore?";
        if ( lOListNames == [])
             sPrompt+="\n\nNo object in list.";
        else
             sPrompt+="\n\nObserve chat for the list.";
    }
    else if (sMsg=="Trusted Avatar")
    {
        lOList=g_lAvWhiteList;
        lOListNames=g_lAvWhiteListNames;
        sPrompt="\n\nWhat avatar do you want to stop trusting?";
        if (lOListNames == [])
             sPrompt+="\n\nNo avatar in list.";
        else
             sPrompt+="\n\nObserve chat for the list.";
    }
    else if (sMsg=="Banned Avatar")
    {
        lOList=g_lAvBlackList;
        lOListNames=g_lAvBlackListNames;
        sPrompt="\n\nWhat avatar do you want not to ban anymore?";
        if (lOListNames == [])
             sPrompt+="\n\nNo avatar in list.";
        else
             sPrompt+="\n\nObserve chat for the list.";
    }
    else
        return;
    g_sListType=sMsg;

    list lButtons=[ALL];
    integer i;
    for (i=0;i<llGetListLength(lOList);++i)     // IW PATCH
    {
        lButtons+=(string)(i+1);
        Notify(kID, (string)(i+1)+": "+llList2String(lOListNames,i)+", "+llList2String(lOList,i), FALSE );
    }
    sPrompt+="\n\nMake a choice:";
    g_kListID = Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth);
}

key Dialog(key kRCPT, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth)
{
    key kID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|"
    + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kID);
    return kID;
}

RemListItem(string sMsg, integer iAuth)
{
    integer i=((integer) sMsg) -1;
    if (g_sListType=="Banned Avatar")
    {
        if (sMsg==ALL)
        {
            g_lAvBlackList=[];
            g_lAvBlackListNames=[];
            return;
        }
        if  (i<llGetListLength(g_lAvBlackList))     // IW PATCH
        {
            g_lAvBlackList=llDeleteSubList(g_lAvBlackList,i,i);
            g_lAvBlackListNames=llDeleteSubList(g_lAvBlackListNames,i,i);
        }
    }
    else if (g_sListType=="Banned Object")
    {
        if (sMsg==ALL)
        {
            g_lObjBlackList=[];
            g_lObjBlackListNames=[];
            return;
        }
        if  (i<llGetListLength(g_lObjBlackList))     // IW PATCH
        {
            g_lObjBlackList=llDeleteSubList(g_lObjBlackList,i,i);
            g_lObjBlackListNames=llDeleteSubList(g_lObjBlackListNames,i,i);
        }
    }
    else if (iAuth==COMMAND_WEARER && g_iMinBaseMode > 0)
    {
        llOwnerSay("Sorry, your owner does not allow you to remove trusted sources.");
    }
    else if (g_sListType=="Trusted Object")
    {
        if (sMsg==ALL)
        {
            g_lObjWhiteList=[];
            g_lObjWhiteListNames=[];
            return;
        }
        if  (i<llGetListLength(g_lObjWhiteList))     // IW PATCH
        {
            g_lObjWhiteList=llDeleteSubList(g_lObjWhiteList,i,i);
            g_lObjWhiteListNames=llDeleteSubList(g_lObjWhiteListNames,i,i);
        }
    }
    else if (g_sListType=="Trusted Avatar")
    {
        if (sMsg==ALL)
        {
            g_lAvWhiteList=[];
            g_lAvWhiteListNames=[];
            return;
        }
        if  (i<llGetListLength(g_lAvWhiteList))     // IW PATCH
        {
            g_lAvWhiteList=llDeleteSubList(g_lAvWhiteList,i,i);
            g_lAvWhiteListNames=llDeleteSubList(g_lAvWhiteListNames,i,i);
        }
    }
}

refreshRlvListener()
{
    llListenRemove(g_iRlvListener);
    if (g_iRLV && g_iBaseMode && !g_iRecentSafeword)
        g_iRlvListener = llListen(RELAY_CHANNEL, "", NULL_KEY, "");
}

CleanQueue()
{
    //clean newly iNumed events, while preserving the order of arrival for every device
    list lOnHold=[];
    integer i=0;
    integer Len = llGetListLength(g_lQueue)/QSTRIDES;   // IW PATCH
    while (i < Len)     // IW PATCH
    {
        string sIdent = llList2String(g_lQueue,0); //GetQident(0)
        key kObj = llList2String(g_lQueue,1); //GetQObj(0);
        string sCommand = llList2String(g_lQueue,2); //GetQCom(0);
        key kUser = NULL_KEY;
        integer iGotWho = llGetSubString(sCommand,0,6)=="!x-who/";
        if (iGotWho)
             kUser=SanitizeKey(llGetSubString(sCommand,7,42));
        integer iAuth=Auth(kObj,kUser);
        if(~llListFindList(lOnHold,[kObj]))
             ++i;
        else if(iAuth==1 && (kUser!=NULL_KEY || !iGotWho)) // !x-who/NULL_KEY means unknown user
        {
            g_lQueue = llDeleteSubList(g_lQueue,i,i+QSTRIDES-1); //DeleteQItem(i);
            HandleCommand(sIdent,kObj,sCommand,TRUE);
        }
        else if(iAuth==-1)
        {
            g_lQueue = llDeleteSubList(g_lQueue,i,i+QSTRIDES-1); //DeleteQItem(i);
            list lCommands = llParseString2List(sCommand,["|"],[]);
            integer j;
            for (j=0;j<llGetListLength(lCommands);++j)     // IW PATCH
                sendrlvr(sIdent,kObj,llList2String(lCommands,j),"ko");
        }
        else
        {
            ++i;
            lOnHold+=[kObj];
        }
    }
    //end of cleaning, now check if there is still events in queue and act accordingly
    Dequeue();
}

// returns TRUE if it was a user command, FALSE if it is a LM from another subsystem
integer UserCommand(integer iNum, string sStr, key kID)
{
    if (iNum<COMMAND_OWNER || iNum>COMMAND_WEARER)
         return FALSE;
    if (llSubStringIndex(sStr,"relay") && sStr != "menu "+g_sSubMenu)
         return TRUE;
    if (iNum == COMMAND_OWNER && sStr == "runaway")
    {
        g_lCollarOwnersList = g_lCollarSecOwnersList = g_lCollarBlackList = [];
        return TRUE;
    }
    if (!g_iRLV)
    {
        Notify(kID, "RLV features are now disabled in this " + CTYPE + ". You can enable those in RLV submenu. Opening it now.", FALSE);
        llMessageLinked(LINK_SET, iNum, "menu RLV", kID);
    }
    else if (sStr=="relay" || sStr == "menu "+g_sSubMenu)
         Menu(kID, iNum);
    else if ((sStr=llGetSubString(sStr,6,-1))=="minmode")
         MinModeMenu(kID, iNum);
    else if (iNum!=COMMAND_OWNER&&kID!=g_kWearer)
        Notify(kID, "Sorry, only the wearer of the " + CTYPE + " or their owner can change the relay options.", FALSE);
    else if (sStr=="safeword")
         SafeWord();
    else if (sStr=="getdebug")
    {
        g_kDebugRcpt = kID;
        Notify(kID, "Relay messages will be forwarded to "+llKey2Name(kID)+".", TRUE);
        return TRUE;
    }
    else if (sStr=="stopdebug")
    {
        g_kDebugRcpt = NULL_KEY;
        Notify(kID, "Relay messages will not forwarded anymore.", TRUE);
        return TRUE;
    }
    else if (sStr=="pending")
    {
        if (g_lQueue != [])
             Dequeue();
        else
             llOwnerSay("No pending relay request for now.");
    }
    else if (sStr=="access")
         ListsMenu(kID, iNum);
    else if (iNum == COMMAND_OWNER && !llSubStringIndex(sStr,"minmode"))
    {
        sStr=llGetSubString(sStr,8,-1);
        integer iOSuccess = 0;
        string sChangetype = llList2String(llParseString2List(sStr, [" "], []),0);
        string sChangevalue = llList2String(llParseString2List(sStr, [" "], []),1);
        if (sChangetype=="safeword")
        {
            if (sChangevalue == "on")
                 g_iMinSafeMode = TRUE;
            else if (sChangevalue == "off")
            {
                g_iMinSafeMode = FALSE;
                g_iSafeMode = FALSE;
            }
            else
                 iOSuccess = 3;
        }
        else if (sChangetype=="land")
        {
            if (sChangevalue == "off")
                 g_iMinLandMode = FALSE;
            else if (sChangevalue == "on")
            {
                g_iMinLandMode = TRUE;
                g_iLandMode = TRUE;
            }
            else
                 iOSuccess = 3;
        }
        else if (sChangetype=="playful")
        {
            if (sChangevalue == "off")
                 g_iMinPlayMode = FALSE;
            else if (sChangevalue == "on")
            {
                g_iMinPlayMode = TRUE;
                g_iPlayMode = TRUE;
            }
            else
                 iOSuccess = 3;
        }
        else
        {
            integer modetype = llListFindList(["off", "restricted", "ask", "auto"], [sChangetype]);
            if (~modetype)
            {
                g_iMinBaseMode = modetype;
                if (modetype > g_iBaseMode)
                     g_iBaseMode = modetype;
            }
            else
                iOSuccess = 3;
        }
        if (!iOSuccess)
        {
            Notify(kID, WEARERNAME+"'s relay minimal authorized mode is successfully set to: "+Mode2String(TRUE), TRUE);
            SaveSettings();
            refreshRlvListener();
        }
        else
             Notify(kID, "Unknown relay mode.", FALSE);
    }
    else
    {
        integer iWSuccess = 0; //0: successful, 1: forbidden because of minmode, 2: forbidden because grabbed, 3: unrecognized commad
        string sChangetype = llList2String(llParseString2List(sStr, [" "], []),0);
        string sChangevalue = llList2String(llParseString2List(sStr, [" "], []),1);
        if (sChangetype=="safeword")
        {
            if (sChangevalue == "on")
            {
                if (g_iMinSafeMode == FALSE)
                     iWSuccess = 1;
                else if (g_lSources!=[])
                     iWSuccess = 2;
                else
                     g_iSafeMode = TRUE;
            }
            else if (sChangevalue == "off")
                 g_iSafeMode = FALSE;
            else
                 iWSuccess = 3;
        }
        else if (sChangetype=="land")
        {
            if (sChangevalue == "off")
            {
                if (g_iMinLandMode == TRUE)
                     iWSuccess = 1;
                else
                     g_iLandMode = FALSE;
            }
            else if (sChangevalue == "on")
                 g_iLandMode = TRUE;
            else
                 iWSuccess = 3;
        }
        else if (sChangetype=="playful")
        {
            if (sChangevalue == "off")
            {
                if (g_iMinPlayMode == TRUE)
                     iWSuccess = 1;
                else
                     g_iPlayMode = FALSE;
            }
            else if (sChangevalue == "on")
                 g_iPlayMode = TRUE;
            else
                 iWSuccess = 3;
        }
        else
        {
            integer modetype = llListFindList(["off", "restricted", "ask", "auto"], [sChangetype]);
            if (~modetype)
            {
                if (modetype >= g_iMinBaseMode)
                     g_iBaseMode = modetype;
                else
                     iWSuccess = 1;
            }
            else
                 iWSuccess = 3;
        }
        if (!iWSuccess)
             Notify(kID, "Your relay mode is successfully set to: "+Mode2String(FALSE), TRUE);
        else if (iWSuccess == 1)
             Notify(kID, "Minimal mode previously set by owner does not allow this setting. Change it or have it changed first.", TRUE);
        else if (iWSuccess == 2)
             Notify(kID, "Your relay is being locked by at least one object, you cannot disable it or enable safewording now.", TRUE);
        else if (iWSuccess == 3)
             Notify(kID, "Invalid command, please read the manual.", FALSE);
        SaveSettings();
        refreshRlvListener();
    }
    return TRUE;
}

default
{
    state_entry()
    {
        g_sScript = llStringTrim(llList2String(llParseString2List(llGetScriptName(), ["-"], []), 1), STRING_TRIM) + "_";
        g_kWearer = llGetOwner();
        WEARERNAME = llGetDisplayName(g_kWearer);
        if (WEARERNAME == "???" || WEARERNAME == "")
            WEARERNAME = llKey2Name(g_kWearer);
        g_lSources=[];
        llSetTimerEvent(g_iGarbageRate); //start garbage collection timer
    }

    link_message(integer iSender_iNum, integer iNum, string sStr, key kID )
    {
        if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
            llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, NULL_KEY);
        else if (iNum==CMD_ADDSRC)
            g_lSources+=[kID];
        else if (iNum==CMD_REMSRC)
        {
            integer i= llListFindList(g_lSources,[kID]);
            if (~i)
                 g_lSources=llDeleteSubList(g_lSources,i,i);
        }
        else if (UserCommand(iNum, sStr, kID))
             return;
        else if ((iNum == LM_SETTING_RESPONSE || iNum == LM_SETTING_DELETE) && llSubStringIndex(sStr, "Global_WearerName") == 0 )
        {
            integer iInd = llSubStringIndex(sStr, "=");
            string sValue = llGetSubString(sStr, iInd + 1, -1);
            //We have a broadcasted change to WEARERNAME to work with
            if (iNum == LM_SETTING_RESPONSE)
                WEARERNAME = sValue;
            else
            {
                g_kWearer = llGetOwner();
                WEARERNAME = llGetDisplayName(g_kWearer);
                if (WEARERNAME == "???" || WEARERNAME == "")
                    WEARERNAME = llKey2Name(g_kWearer);
            }
        }
        else if (iNum == LM_SETTING_RESPONSE)
        {   //this is tricky since our db value contains equals signs
            //split string on both comma and equals sign
            //first see if this is the token we care about
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if (sToken == g_sScript + "settings")
                 UpdateSettings(sValue);
            else if (sToken == "Global_CType")
                 CTYPE = sValue;
            else if (sToken == "auth_owner")
                 g_lCollarOwnersList = llParseString2List(sValue, [","], []);
            else if (sToken == "auth_secowners")
                 g_lCollarSecOwnersList = llParseString2List(sValue, [","], []);
            else if (sToken == "auth_blacklist")
                 g_lCollarBlackList = llParseString2List(sValue, [","], []);
        }
        else if (iNum == LM_SETTING_SAVE)
        {   //this is tricky since our db sValue contains equals signs
            //split string on both comma and equals sign
            //first see if this is the sToken we care about
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if (sToken == "auth_owner")
                 g_lCollarOwnersList = llParseString2List(sValue, [","], []);
            else if (sToken == "auth_secowners")
                 g_lCollarSecOwnersList = llParseString2List(sValue, [","], []);
            else if (sToken == "auth_blacklist")
                 g_lCollarBlackList = llParseString2List(sValue, [","], []);
        }
        // rlvoff -> we have to turn the menu off too
        else if (iNum == RLV_OFF)
        {
            g_iRLV=FALSE;
            refreshRlvListener();
        }
        // rlvon -> we have to turn the menu on again
        else if (iNum == RLV_ON)
        {
            g_iRLV=TRUE;
            refreshRlvListener();
        }
        else if (iNum==RLV_REFRESH)
        {
            g_iRLV=TRUE;
            refreshRlvListener();
        }
        else if (iNum == DIALOG_RESPONSE)
        {
            if (~llListFindList([g_kMenuID, g_kMinModeMenuID, g_kListMenuID, g_kListID, g_kAuthMenuID], [kID]))
            {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                key kAv = llList2Key(lMenuParams, 0);
                string sMsg = llList2String(lMenuParams, 1);
                integer iPage = llList2Integer(lMenuParams, 2);
                integer iAuth = llList2Integer(lMenuParams, 3);
                if (kID==g_kMenuID || kID == g_kMinModeMenuID)
                {
                    llSetTimerEvent(g_iGarbageRate);
                    integer iIndex=llListFindList(["Auto","Ask","Restricted","Off","Safeword", "+ Safeword", "- Safeword","+ Playful","- Playful","+ Land","- Land"],[sMsg]);
                    if (sMsg=="Pending")
                        UserCommand(iAuth, "relay pending", kAv);
                    else if (sMsg=="Access Lists")
                        UserCommand(iAuth, "relay access", kAv);
                    else if (~iIndex)
                    {
                        string sInternalCommand = "relay ";
                        if (kID == g_kMinModeMenuID)
                            sInternalCommand += "minmode ";
                        sInternalCommand += llList2String(["auto","ask","restricted","off","safeword","safeword on","safeword off","playful on", "playful off","land on","land off"],iIndex);
                        UserCommand(iAuth, sInternalCommand, kAv);
                        if (kID == g_kMinModeMenuID)
                            MinModeMenu(kAv, iAuth);
                        else
                           Menu(kAv, iAuth);
                    }
                    else if (sMsg=="Grabbed by")
                    {
                        llMessageLinked(LINK_SET, iAuth,"showrestrictions",kAv);
                        Menu(kAv, iAuth);
                    }
                    else if (sMsg=="MinMode")
                        MinModeMenu(kAv, iAuth);
                    else if (sMsg=="Help")
                    {
                        llGiveInventory(kAv,"OpenCollar Guide");
                        Menu(kAv, iAuth);
                    }
                    else if (sMsg==UPMENU)
                    {
                        if (kID == g_kMenuID) llMessageLinked(LINK_SET,iAuth,"menu "+g_sParentMenu,kAv);
                        else Menu(kAv, iAuth);
                    }
                }
                else if (kID==g_kListMenuID)
                {
                    llSetTimerEvent(g_iGarbageRate);
                    PListsMenu(kAv,sMsg, iAuth);
                }
                else if (kID==g_kListID)
                {
                    llSetTimerEvent(g_iGarbageRate);
                    if (sMsg==UPMENU)
                        ListsMenu(kAv, iAuth);
                    else
                    {
                        RemListItem(sMsg, iAuth);
                        ListsMenu(kAv, iAuth);
                    }
                }
                else if (kID==g_kAuthMenuID)
                {
                    llSetTimerEvent(g_iGarbageRate);
                    g_iAuthPending = FALSE;
                    key kCurID=llList2String(g_lQueue,1); //GetQObj(0);
                    string sCom = llList2String(g_lQueue,2);  //GetQCom(0));
                    key kUser = NULL_KEY;
                    integer iSave=TRUE;
                    if (llGetSubString(sCom,0,6)=="!x-who/")
                        kUser = SanitizeKey(llGetSubString(sCom,7,42));
                    if (sMsg=="Yes")
                    {
                        g_lTempWhiteList+=[kCurID];
                        if (kUser)
                             g_lTempUserWhiteList+=[(string)kUser];
                        iSave=FALSE;
                    }
                    else if (sMsg=="No")
                    {
                        g_lTempBlackList+=[kCurID];
                        if (kUser)
                             g_lTempUserBlackList+=[(string)kUser];
                        iSave=FALSE;
                    }
                    else if (sMsg=="Trust Object")
                    {
                        if (!~llListFindList(g_lObjWhiteList, [kCurID]))
                        {
                            g_lObjWhiteList+=[kCurID];
                            g_lObjWhiteListNames+=[llKey2Name(kCurID)];
                        }
                    }
                    else if (sMsg=="Ban Object")
                    {
                        if (!~llListFindList(g_lObjBlackList, [kCurID]))
                        {
                            g_lObjBlackList+=[kCurID];
                            g_lObjBlackListNames+=[llKey2Name(kCurID)];
                        }
                    }
                    else if (sMsg=="Trust Owner")
                    {
                        if (!~llListFindList(g_lAvWhiteList, [(string)llGetOwnerKey(kCurID)]))
                        {
                            g_lAvWhiteList+=[(string)llGetOwnerKey(kCurID)];
                            g_lAvWhiteListNames+=[llGetDisplayName(llGetOwnerKey(kCurID))+"("+llKey2Name(llGetOwnerKey(kCurID))+")"];
                        }
                    }
                    else if (sMsg=="Ban Owner")
                    {
                        if (!~llListFindList(g_lAvBlackList, [(string)llGetOwnerKey(kCurID)]))
                        {
                            g_lAvBlackList+=[(string)llGetOwnerKey(kCurID)];
                            g_lAvBlackListNames+=[llGetDisplayName(llGetOwnerKey(kCurID))+"("+llKey2Name(llGetOwnerKey(kCurID))+")"];
                        }
                    }
                    else if (sMsg=="Trust User")
                    {
                        if (!~llListFindList(g_lAvWhiteList, [(string)kUser]))
                        {
                            g_lAvWhiteList+=[(string)kUser];
                            g_lAvWhiteListNames+=[llGetDisplayName(llGetOwnerKey(kUser))+"("+llKey2Name(llGetOwnerKey(kUser))+")"];
                        }
                    }
                    else if (sMsg=="Ban User")
                    {
                        if (!~llListFindList(g_lAvBlackList, [(string)kUser]))
                        {
                            g_lAvBlackList+=[(string)kUser];
                            g_lAvBlackListNames+=[llGetDisplayName(llGetOwnerKey(kUser))+"("+llKey2Name(llGetOwnerKey(kUser))+")"];
                        }
                    }
                    if (iSave)
                         SaveSettings();
                    CleanQueue();
                }
            }
        }
        else if (iNum == DIALOG_TIMEOUT)
        {
            if (kID == g_kAuthMenuID)
            {
                g_iAuthPending = FALSE;
                llOwnerSay("Relay authorization dialog expired. You can make it appear again with command \"<prefix>relay pending\".");
            }
        }
    }

    listen(integer iChan, string who, key kID, string sMsg)
    {

        list lArgs=llParseString2List(sMsg,[","],[]);
        sMsg = "";  // free up memory in case of large messages
        if (llGetListLength (lArgs) !=3)
             return;
        if (llList2Key(lArgs,1)!=g_kWearer && llList2String(lArgs,1)!="ffffffff-ffff-ffff-ffff-ffffffffffff")
             return; // allow FFF...F wildcard
        string sIdent=llList2String(lArgs,0);
        sMsg=llToLower(llList2String(lArgs,2));
        if (g_kDebugRcpt == g_kWearer)
             llOwnerSay("To relay: "+sIdent+","+sMsg);
        else if (g_kDebugRcpt)
             llRegionSayTo(g_kDebugRcpt, DEBUG_CHANNEL, "To relay: "+sIdent+","+sMsg);
        if (sMsg == "!pong")
        {//sloppy matching; the protocol document is stricter, but some in-world devices do not respect it
            llMessageLinked(LINK_SET, COMMAND_RLV_RELAY, "ping,"+(string)g_kWearer+",!pong", kID);
            return;
        }
        lArgs = [];  // free up memory in case of large messages

        key kUser = NULL_KEY;
        if (llGetSubString(sMsg,0,6)=="!x-who/")
             kUser=SanitizeKey(llGetSubString(sMsg,7,42));
        integer iAuth=Auth(kID,kUser);
        if (iAuth==-1)
             return;
        else if (iAuth==1)
        {
            HandleCommand(sIdent,kID,sMsg,TRUE);
            llSetTimerEvent(g_iGarbageRate);
        }
        else if (g_iBaseMode == 2)
        {
            g_lQueue += [sIdent, kID, sMsg];
            sMsg = ""; sIdent="";
            if (llGetMemoryLimit() - llGetUsedMemory()< 3927) //keeps margin for this event + next arriving chat message
            {
                sMsg = ""; sIdent="";
                key kOldestId = llList2Key(g_lQueue, 1);  // It's actually more likely we want to drop the old request we completely forgot about rather than the newest one that will be forgotten because of some obscure memory limit.
                llOwnerSay("Relay queue saturated. Dropping all requests from oldest source ("+ llKey2Name(kOldestId) +").");
                g_lTempBlackList+=[kOldestId];
                CleanQueue();
            }
            if (!g_iAuthPending)
             Dequeue();
        }
        else if (g_iPlayMode) {HandleCommand(sIdent,kID,sMsg,FALSE); llSetTimerEvent(g_iGarbageRate);}
    }

    on_rez(integer iNum)
    {
        llResetScript();
    }

    timer()
    {
        if (g_iRecentSafeword)
        {
            g_iRecentSafeword = FALSE;
            refreshRlvListener();
        }
        //garbage collection
        vector vMyPos = llGetRootPosition();
        integer i;
        for (i=0;i<llGetListLength(g_lSources);++i)     // IW PATCH
        {
            key kID = llList2Key(g_lSources,i);
            vector vObjPos = llList2Vector(llGetObjectDetails(kID, [OBJECT_POS]),0);
            if (vObjPos == <0, 0, 0> || llVecDist(vObjPos, vMyPos) > 100) // 100: max shout distance
            {
                string kIDs = (string)kID; //we need to check kID is a valid key
                list params = llParseString2List(kIDs, ["-"], []);//split key at '-'
                string kNewOwner1 = llList2String(params, 4);//grab the last segment
                if (kNewOwner1 !="")//A valid key would have something here
                llMessageLinked(LINK_SET,RLV_CMD,"clear",kID);
            }
        }
        llSetTimerEvent(g_iGarbageRate);
        g_lTempBlackList=[];
        g_lTempWhiteList=[];
        if (g_lSources == [])
        { //dont clear already authorized users before done with current session
            g_lTempUserBlackList=[];
            g_lTempUserWhiteList=[];
        }
    }
}