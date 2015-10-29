#!/bin/bash

# update this stuff to fit your hashcat environment
hashcat_dir="/home/gul/work/tools/passwords/hashcat"
hashcat_bin="${hashcat_dir}/hashcat-cli64.bin"
# hashcat_bin="${hashcat_dir}//cudaHashcat64"
hashcat_masks_dir="${hashcat_dir}/masks"
hashcat_rules_dir="${hashcat_dir}/rules"
hashcat_pot="./hashcat.pot"
hashcat_logfile="./hashcat-ng.log"
dico_dir="/home/gul/work/tools/dictionaries/sort/"

usage() {
    filename=$(echo $0 | sed 's@.*/@@')
    echo "Usage: ${filename} (--resume <resumehash>) <hashtype> <hashfile> <dict>"
    echo "       hashtype: hashcat type NTLMv1 = 5500, NTLMv2 = 5600, etc. RTFM :)"
    echo "       hashfile: Contains hashes with the following format: username::computer-or-domainname:...stuff..."
    echo "       dict:     Dictionnar(y/ies) or director(y/ies) containing dictionnar(y/ies). Both can be mixed. Go crazy."
}


get_resume_hash() {
    echo "$(echo $1 | md5sum | cut -d ' ' -f 1)"
}

log_step() {
    echo "$(date '+%Y:%m:%d %H:%M:%S') - ${1}"  >> "${hashcat_logfile}"
    echo "Resume Hash: " $(get_resume_hash "${1}") >> "${hashcat_logfile}"
}

cleanup() {
    rm -f "${hashfile_purged}"
    return $?
}

control_c() {
    echo -e "\nExiting due to control-c interrupt" | tee -a $logfile
    cleanup
    exit $?
}

trap control_c SIGINT

purge_hashfile() {
    if [ ! -f "${hashfile_purged}" ] || [ "${hashcat_pot_length}" != "$(wc -l ${hashcat_pot})" ]; then
	tmp_date="./.tmp_hashcat_found_hashes_$(date '+%Y_%m_%d-%H_%M_%S')"
	# [ -f "${hashcat_pot}" ] && grep -i -o -f "${hashfile}" "${hashcat_pot}" | sort -u > "${tmp_date}"
	# [ -f "${tmp_date}" ]    && grep -i -f  "${tmp_date}" -v "${hashfile}" > "${hashfile_purged}"
	# [ -f "${tmp_date}" ]    && rm -f "${tmp_date}"
	tmp_pot="./.tmp_hashcat_pot_$(date '+%Y_%m_%d-%H_%M_%S')"
	[ -f "${hashcat_pot}" ] && sort -u "${hashcat_pot}" > "${tmp_pot}"
	if [ -f "${tmp_pot}" ] ; then
	    while read hash ; do
		grep -o "${hash}" "${tmp_pot}" >> "${tmp_date}"
	    done < "${hashfile}"
	fi
	[ -f "${tmp_date}" ] && grep -f "${tmp_date}" -v "${hashfile}" > "${hashfile_purged}"
	[ -f "${tmp_date}" ] && rm   -f "${tmp_date}"
	[ -f "${tmp_pot}"  ] && rm   -f "${tmp_pot}"
    fi
}


crack_check() {
    step=$1
    if [ -z "${resumehash}" ] || [ "${resumehash}" = $(get_resume_hash "${step}") ]; then
	unset resumehash
	purge_hashfile
	log_step "${step}"
	return 0
    # else
    # 	[ -n "${resumehash}" ] && echo "Skipping ${step} => " $(get_resume_hash "${step}")
    fi
    return -1
}

if [ $# -lt 2 ] || ( [ "${1}" = "--resume" ] && [ $# -lt 4 ] ) ; then
    usage ;
    exit 1
fi

if [ "${1}" = "--resume" ]; then
    shift
    resumehash=$1 ; shift
fi

hashtype=$1 ; shift
hashfile=$1 ; shift

hashfile_purged="${hashfile}.purged"



# backing up pot file
[ ! -f "${hashcat_pot}" ] && touch "${hashcat_pot}"
cp "${hashcat_pot}" "${hashcat_pot}.backup_$(date '+%Y_%m_%d-%H_%M_%S')"

hashcat_pot_length="$(wc -l ${hashcat_pot})"


# The quick stuff
crack_check "Straigt mode"					    && "${hashcat_bin}" -a 0 -m "${hashtype}" "${hashfile_purged}" $* "${dico_dir}"
crack_check "Table lookup mode"					    && "${hashcat_bin}" -a 5 -m "${hashtype}" --table-file "${hashcat_rules_dir}/case_leet2.table" "${hashfile_purged}" $* "${dico_dir}"

for mask in $(cat "${hashcat_masks_dir}/gsr.min8.2hours.netntlmv2.hcmask") ; do
    crack_check "Mask mode (gsr.min8.2hours.netntlmv2.hcmask): ${mask}" && "${hashcat_bin}" -a 3 -m "${hashtype}" "${hashfile_purged}" "${mask}"
done

# Rapid rules (kinda)
for rule in best64.rule d3ad0ne.rule hsc_ascii.rules ; do
    crack_check "Rule mode ${rule}" && \
	"${hashcat_bin}" -a 0 -m "${hashtype}" -r           "${hashcat_rules_dir}/${rule}"      "${hashfile_purged}" $* "${dico_dir}"
done

# Time eating rules
for mask in $(cat "${hashcat_masks_dir}/gsr.min8.6hours_skip_first_2hours.netntlmv2.hcmask") ; do
    crack_check "Bruteforce mode with mask (gsr.min8.6hours_skip_first_2hours.netntlmv2.hcmask): ${mask}" && \
	"${hashcat_bin}" -a 3 -m "${hashtype}" "${hashfile_purged}" "${mask}"
done

# add additional cracking methods as needed
cleanup
