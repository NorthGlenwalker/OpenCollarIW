////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                          OpenCollar - remote template                          //
//                                 version 3.995                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to InWorldz     //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2017  Individual Contributors and OpenCollar Official               //
// ------------------------------------------------------------------------------ //
//          http://github.com/NorthGlenwalker/OpenCollarIW                        //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////

// Licensed under the GPLv2, with the additional requirement that these scripts remain "full perms" in Inworldz.  See "OpenCollar License" for details.
key g_kWearer;
key kToucher;

Debug(string in)
{
    //llOwnerSay(llGetScriptName() + ": " + in);
}

integer GetOwnerChannel(key kOwner, integer iOffset)
{
    integer iChan = (integer)("0x"+llGetSubString((string)kOwner,2,7)) + iOffset;
    if (iChan>0)
    {
        iChan=iChan*(-1);
    }
    if (iChan > -10000)
    {
        iChan -= 30000;
    }
    return iChan;
}

default
{
    state_entry()
    {
        // store key of wearer
        g_kWearer = llGetOwner();
    }

    on_rez(integer iParam)
    {
        if (llGetOwner()!=g_kWearer)
        {
            // Reset if wearer changed
            llResetScript();
        }
    }
}
