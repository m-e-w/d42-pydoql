/*  All Devices

	Updated  - 10/14/20
	- Updated view_device_v1 to new view_device_v2
	- Added in the join for cloudinstance	
	- Updated view_hardware_v1 to new view_hardware_v2
	Update - 10/20/21 SDay
	- Created CTE's to improve performance
	- removed 'view_device_custom_fields_flat_v1' from joins as it was not used.
	Update - merged other updates for All Devices  1/31/22
	- Updated the way the MP counts and local storage is calculated and have no decimal places...
	- Updated the way eos/eol is checked - check version also so reduce the "fan-out"
	- Corrected the way building/room/rack was accessed
	- Corrected the way CPU calculation was done so to avoid zero/blank values	
*/	


with 

counts as (
	select 
		d.device_pk,
		(Select count(1) From view_softwaredetails_v1 sd where sd.device_fk = d.device_pk)  "Software Discovered",
	    (Select count(1) From view_serviceinstance_v2 si where si.device_fk = d.device_pk) "Services Discovered",
	    (Select count(1) From view_appcomp_v1 a 		 where  a.device_fk = d.device_pk) "Application Components Discovered",
/*	    (Select count(1) From view_mountpoint_v1 m 		 where m.device_fk  = d.device_pk and
	  			m.fstype_name <> 'nfs' and m.fstype_name <> 'nfs4' and m.filesystem not like '\\\\%') "Local Disk Count",  */
		(Select count(1) From view_mountpoint_v1 m 
		   Where m.device_fk = d.device_pk and lower(m.fstype_name) Not IN ('nfs', 'nfs4', 'cifs', 'smb', 'smbfs', 'dfsfuse_dfs', 'objfs') and m.filesystem not like '\\\\%')"Local Disk Count",	/* update the MP count  1/31/22 */				
	    (Select count(1) From view_mountpoint_v1 mp 	 where mp.device_fk = d.device_pk) "Mounts Discovered",
	    (Select count(1) From view_ipaddress_v1 ip 		 where ip.device_fk = d.device_pk) "IP Addresses Discovered",
	    (Select count(1) From view_part_v1 p 			 where p.device_fk = d.device_pk) "Parts Discovered"
    from  view_device_v2 d
    ),
		
ns as (
	select 
		ns.device_fk,  
		string_agg(ns.name,' | ')  network_shares
	
	From view_networkshare_v1 ns
	group by 1
	),

  /* get the records needed for storage size calculations - windows machines */
	agg_mp_records_win  as (
		Select mp.*
		,dr.device_fk
		From view_mountpoint_v2 mp
		Join view_deviceresource_v1 dr ON dr.resource_fk = mp.mountpoint_pk and lower(dr.relation) = 'mountpoint'
		Where mp.mountpoint = mp.label
	),
 /* Sum up local and remote for window devices  */		
	sum_win_storage  as (
		Select lcl.device_fk, coalesce(lcl.local_stor,0) "Local Storage Size GB", coalesce(lcl.local_stor_free,0) "Local Storage Free Size GB"
							,coalesce(rmt.remote_stor,0) "Remote Storage Size GB", coalesce(rmt.remote_stor_free,0) "Remote Storage Free Size GB", 'WIN' mp_type
		From (Select amrw.device_fk, round(sum(amrw.capacity/1024),0)  local_stor, round(sum(amrw.free_capacity/1024),0)  local_stor_free  
				 From agg_mp_records_win amrw Where (position(':' IN amrw.mountpoint) > 0 and amrw.filesystem is Null) Group by 1) lcl
		Left Join (Select amrw.device_fk, round(sum(amrw.capacity/1024),0) remote_stor, round(sum(amrw.free_capacity/1024),0) remote_stor_free 
					From agg_mp_records_win amrw Where (position('\\' IN amrw.mountpoint) > 0 and amrw.fstype_name is Not Null) Group by 1) rmt ON rmt.device_fk = lcl.device_fk   
	),
 /* get the records needed for storage size calculations - Non-Windows machines machines */	
	agg_mp_records_nix  as (
		Select Distinct on (dr.device_fk, mp.fstype_name, mp.capacity, mp.free_capacity) mp.*
		,dr.device_fk
		From view_mountpoint_v2 mp
		Join view_deviceresource_v1 dr ON dr.resource_fk = mp.mountpoint_pk and lower(dr.relation) = 'mountpoint'
		Where (mp.mountpoint != mp.label or mp.label is Null)
	),
 /* Sum up local and remote for non-window devices (Nix and VMW)  */	
	sum_nix_storage  as (
		Select lcl.device_fk, coalesce(lcl.local_stor ,0) "Local Storage Size GB", coalesce(lcl.local_stor_free,0) "Local Storage Free Size GB"
							,coalesce(rmt.remote_stor ,0) "Remote Storage Size GB", coalesce(rmt.remote_stor_free,0) "Remote Storage Free Size GB", 'NIX' mp_type
		From (Select amrw.device_fk, round(sum(amrw.capacity/1024),0)  local_stor, round(sum(amrw.free_capacity/1024),0)  local_stor_free  
				 From agg_mp_records_nix amrw Where (lower(amrw.fstype_name) IN ('ntfs', 'fat32', 'vfat', 'ext2', 'ext3', 'ext4', 'apfs', 'btrfs', 'dev', 'fd', 'fdescfs', 'ffs', 'udf', 'ufs', 'xfs', 'zfs','vmfs') or amrw.fstype_name is Null) Group by 1) lcl
		Left Join (Select amrw.device_fk, round(sum(amrw.capacity/1024),0) remote_stor, round(sum(amrw.free_capacity/1024),0) remote_stor_free 
					 From agg_mp_records_nix amrw Where (lower(amrw.fstype_name) IN ('nfs', 'nfs4', 'cifs', 'smb', 'smbfs', 'dfsfuse_dfs', 'objfs')) Group by 1) rmt ON rmt.device_fk = lcl.device_fk   
	),
 /* union all the MP records from windows and non-windows machines.  */	
	union_mp_records  as (
		Select win.* 
		From sum_win_storage win 
			Union All
		Select nix.* 
		From sum_nix_storage nix
	), 
/* Replaced with above 1/31/22  	*/
mp as (
	Select 
		mp.device_fk
		,string_agg (mp.filesystem,' | ') mount_points	
	 From (Select Distinct mp1.device_fk, mp1.filesystem From view_mountpoint_v1 mp1) mp
    Group by 1
    ), 
	
ip as (
	Select ip.device_fk ,
		string_agg(ip.ip_address::text, ' | ') all_listener_device_ips,
		string_agg(ip.label, ' | ')  all_labels,
		string_agg(dr.name || '.' || dz.name, ' | ') "DNS Records"
    From view_ipaddress_v1 ip
    join view_dnsrecords_v1 dr on dr.content like '%' || host(ip.ip_address) || '%'
    join view_dnszone_v1 as dz on dz.dnszone_pk = dr.dnszone_fk
    group by 1
    ) ,

    
parts as (
	Select distinct
	        pt.device_fk,
	        string_agg(distinct pm.name, ',') "CPU Model",
	        string_agg(distinct pmv.name, ',') "CPU Manufacturer"
	    From 
	        view_part_v1 pt
	        Left Join view_partmodel_v1 pm ON pm.partmodel_pk = pt.partmodel_fk and pm.type_id = '1'
	        Left Join view_vendor_v1 pmv ON pmv.vendor_pk = pm.vendor_fk
	    Group by 
	        pt.device_fk
	    Having 
	        string_agg(pm.name, ',') is not null and 
	        string_agg(pmv.name, ',') is not null
	    )

Select  distinct
    d.device_pk,
    d.last_edited "Last_Discovered",
    d.name "Device_Name",
    d.in_service "In Service",
    d.service_level "Service_Level",
    d.type "Device_Type",
    d.physicalsubtype "Device Subtype",
    d.virtualsubtype "Virtual_Subtype",
    d.serial_no "Device_Serial",
    d.virtual_host "Virtual Host",
    d.network_device "Network Device",
    d.os_architecture "OS_Arch",
    d.total_cpus "CPU Sockets",
    d.core_per_cpu "Cores Per CPU",
    d.cpu_speed "CPU Speed",
	Case When d.core_per_cpu is Null Then d.total_cpus
		Else d.total_cpus*d.core_per_cpu
	End "Total Cores",	
 /*    d.total_cpus*d.core_per_cpu "Total Cores",   replaced with above to avoid null fields 1/31/22 */
    CASE When d.threads_per_core >= 2      Then 'YES'        Else 'NO'       END "Hyperthreaded",
	CASE When d.ram_size_type = 'GB'      Then d.ram*1024     Else d.ram 	END "RAM",
    v2.name "OS Vendor",
    osc.category_name "OS Category",
    CASE d.os_version         WHEN '' then d.os_name    ELSE coalesce(d.os_name || ' - ' ||    d.os_version,d.os_name)    END "OS Name",
    d.os_version "OS Version",
    d.os_version_no "OS Version Number",
    ose.eol "OS_End of Life",
    ose.eos "OS_End of Support",
    v.name "Manufacturer",
    h.name "Hardware Model",
    d.asset_no "Asset Number",
    counts."Software Discovered",
    counts."Services Discovered",
    counts."Application Components Discovered",
    counts."Local Disk Count",
    counts."Mounts Discovered",
    counts."IP Addresses Discovered",
    counts."Parts Discovered",
    d.bios_version "BIOS Version",
    d.bios_revision "BIOS Revision",
    d.bios_release_date "BIOS Release Date",
    sr.name "Storage Room",
    b.name "Building Name",
    m.name "Room Name",
    r.row "Row Name",
    r.name "Rack Name",
    h.size "Size (RU)",
    ns.network_shares,
 	mp.mount_points,
    ci.vendor_fk,
    ci.account,
    cv.name "Cloud Service Provider",
    ci.service_name "Cloud Service Name",
    ci.instance_id "Cloud Instance ID",
    ci.instance_name "Cloud Instance Name",
    ci.instance_type "Cloud Instance Type",
    ci.status "Cloud Instance Status",
    ci.location "Cloud Location",
    ci.notes "Cloud Notes",
    pch.po_date "PO Date",
    pch.cost "PO Cost",
    pli.cost "Line Item Cost",
    pch.order_no "Order Number",
    pch.cc_code "Cost Center",
    pch.cc_description "Cost Center Description",
	ip.all_listener_device_ips,
   	ip.all_labels,
  	ip."DNS Records",
	/* added 1/31/22  */
    umr."Local Storage Size GB" - umr."Local Storage Free Size GB" "Used Space",
	umr."Local Storage Size GB" "Total Space",
    umr."Local Storage Free Size GB" "Total Free Space",	
/*  replace 1/31/22    
	mp."Used Space",
    mp."Total Space",
    mp."Total Free Space",  */
    parts."CPU Model",
    parts."CPU Manufacturer"
From view_device_v2 d
	left join counts on										counts.device_pk = d.device_pk 
    Left Join view_cloudinstance_v1 ci ON 					ci.device_fk = d.device_pk
    Left Join view_purchaselineitems_to_devices_v1 ptd ON 	ptd.device_fk = d.device_pk
    Left Join view_purchaselineitem_v1 pli ON 				ptd.purchaselineitem_fk = pli.purchaselineitem_pk
    Left Join view_purchase_v1 pch ON 						pch.purchase_pk = pli.purchase_fk
    Left Join view_oseoleos_v1 ose ON 						ose.os_fk = d.os_fk  and ose.version = d.os_version  /* 1/31/22  reduce fan-out  */
    Left Join view_hardware_v2 h ON 						d.hardware_fk = h.hardware_pk
    Left Join view_vendor_v1 v ON 							h.vendor_fk = v.vendor_pk
    Left Join view_vendor_v1 cv ON 							ci.vendor_fk = cv.vendor_pk
    Left Join view_room_v1 sr ON 							sr.room_pk = d.storage_room_fk 
    Left Join view_rack_v1 r ON 							r.rack_pk = d.calculated_rack_fk
    Left Join view_room_v1 m ON 							m.room_pk = d.calculated_room_fk 
    Left Join view_building_v1 b ON 						b.building_pk = d.calculated_building_fk
    Left Join view_os_v1 osc ON 							osc.os_pk = d.os_fk
    Left Join view_vendor_v1 v2 ON 							v2.vendor_pk = osc.vendor_fk 
  --  Left Join view_device_custom_fields_flat_v1 dcf ON 		dcf.device_fk = d.device_pk
    Left Join parts ON 										parts.device_fk = d.device_pk
    Left join ns		on									ns.device_fk = d.device_pk
	Left Join union_mp_records umr ON 						umr.device_fk = d.device_pk	  /*  New MP calc - 1/31/22  */
    Left join mp on 										mp.device_fk = d.device_pk   /* just the MP filesystem names 1/31/22  */
    left join ip on 										ip.device_fk  = d.device_pk 
	Order by d.name asc