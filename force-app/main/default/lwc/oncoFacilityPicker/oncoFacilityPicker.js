import { LightningElement, api, track } from 'lwc';

export default class OncoFacilityPicker extends LightningElement {

     // default city, can be set from App Builder
    @api value
   
    connectedCallback(){
        console.log('Value:',JSON.stringify(this.value));
    }
}
